package bvd.zb;

import java.lang.reflect.Array;
import java.lang.reflect.Field;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import org.joml.Vector3f;
import zombie.GameTime;
import zombie.SandboxOptions;
import zombie.SandboxOptions.SandboxOption;
import zombie.core.physics.Bullet;
import zombie.core.physics.WorldSimulation;
import zombie.debug.DebugLog;
import zombie.iso.IsoChunk;
import zombie.iso.IsoChunkMap;
import zombie.iso.IsoFloorBloodSplat;
import zombie.iso.IsoWorld;
import zombie.scripting.ScriptManager;
import zombie.scripting.objects.VehicleScript;
import zombie.vehicles.BaseVehicle;

// BVD's WorldSimulation layer under ZombieBuddy: the same impulse scaling,
// mass normalisation, script retune and world-tick tyre-mark expiry that the
// manual install's patched WorldSimulation carries, attached to vanilla's
// physics step through Patches instead of a replaced class.
public final class BvdWorld {
   // Live, frame-recomputed scale that keeps the heaviest vehicle on the cell
   // at a stable simulated mass; BvdCar scales drive force and drag by it.
   public static float massScaler = 1.0F;

   // Reflection handles into BaseVehicle's private impulse accumulators.
   private static Field hitImpulseList;
   private static Field squishImpulseArray;
   private static Field impulseVector;
   private static Field impulseEnabled;
   private static boolean reflectionReady;

   private static final Vector3f impulseProbe = new Vector3f();
   // Corpse-shove rate limiter, keyed by vehicle id; pruned to live vehicles
   // every frame because PZ recycles ids.
   private static final HashMap<Integer, Float> corpseCooldown = new HashMap<>();
   private static final HashSet<Integer> liveIds = new HashSet<>();
   private static long skidPruneMs = 0L;

   private BvdWorld() {
   }

   private static float sandbox(String name, float fallback) {
      SandboxOption opt = SandboxOptions.instance.getOptionByName(name);
      if (opt == null) {
         return fallback;
      }
      try {
         return (float)Double.parseDouble(opt.asConfigOption().getValueAsString());
      } catch (NumberFormatException badValue) {
         return fallback;
      }
   }

   public static void beforeCreate(WorldSimulation ws) {
      if (!Hooks.enabled || ws.created) {
         return;
      }
      try {
         hitImpulseList = BaseVehicle.class.getDeclaredField("impulsesFromHitObjects");
         hitImpulseList.setAccessible(true);
         squishImpulseArray = BaseVehicle.class.getDeclaredField("impulsesFromSquishedBodies");
         squishImpulseArray.setAccessible(true);
         Class<?> impulseClass = Class.forName("zombie.vehicles.BaseVehicle$VehicleImpulse");
         impulseVector = impulseClass.getDeclaredField("impulse");
         impulseVector.setAccessible(true);
         impulseEnabled = impulseClass.getDeclaredField("enable");
         impulseEnabled.setAccessible(true);
         reflectionReady = true;
      } catch (ReflectiveOperationException | RuntimeException e) {
         DebugLog.log("BetterVehicleDynamics: reflection init failed (" + e + "); impulse scaling disabled, vanilla physics retained");
         reflectionReady = false;
         return;
      }

      // Lower every vehicle script's stopping-movement force; the base value
      // is too grabby once impulses are softened.
      ArrayList<VehicleScript> scripts = ScriptManager.instance.getAllVehicleScripts();
      DebugLog.log("BetterVehicleDynamics: retuning " + scripts.size() + " vehicle script(s)");
      for (int i = 0; i < scripts.size(); i++) {
         VehicleScript script = scripts.get(i);
         try {
            script.Load(script.getName(), "{ stoppingMovementForce = 0.01, }");
         } catch (Exception loadFailed) {
            DebugLog.log("BetterVehicleDynamics: could not retune script " + script.getName());
         }
         script.toBullet();
      }
   }

   // Once per frame, before the substeps: find the heaviest vehicle so the
   // simulated mass can be clamped to a stable ceiling (10 kg floor guards an
   // empty cell), and drop cooldowns of vehicles no longer on the cell.
   public static void beforePhysicsFrame() {
      if (!Hooks.enabled) {
         return;
      }
      float heaviest = 10.0F;
      liveIds.clear();
      for (BaseVehicle scan : IsoWorld.instance.currentCell.getVehicles()) {
         liveIds.add((int)scan.vehicleId);
         float m = scan.getMass();
         if (m > heaviest) {
            heaviest = m;
         }
      }
      massScaler = Math.min(1.0F, 750.0F / heaviest);
      corpseCooldown.keySet().retainAll(liveIds);
   }

   // Replaces vanilla's updateVehiclePhysics() for one substep.
   public static boolean vehicleSubstep() {
      if (!Hooks.enabled) {
         return false;
      }
      for (BaseVehicle vehicle : IsoWorld.instance.currentCell.getVehicles()) {
         Bullet.setVehicleMass(vehicle.vehicleId, vehicle.getMass() * massScaler);
         float massSoften = Math.min(1.5F, 1000.0F / vehicle.getFudgedMass());
         applyImpulseScaling(vehicle, massSoften);
         vehicle.applyAccumulatedImpulsesFromHitObjectsToPhysics();
         vehicle.applyAllImpulsesFromProneCharacters();
         vehicle.checkSurroundingChunks();
      }
      return true;
   }

   // Rescale the queued shove impulses before vanilla applies them: foliage
   // and zombie strikes by ShoveFoliage / ShoveZombies, a squished body by
   // ShoveCorpses with an extra 2.0 weighting, rate-limited so rolling over a
   // pile does not fling the vehicle.
   private static void applyImpulseScaling(BaseVehicle vehicle, float massSoften) {
      if (!reflectionReady) {
         return;
      }
      try {
         ArrayList<?> hitList = (ArrayList<?>)hitImpulseList.get(vehicle);
         int hitCount = hitList.size();
         for (int idx = 0; idx < hitCount; idx++) {
            Vector3f impulse = (Vector3f)impulseVector.get(hitList.get(idx));
            // A foliage hit cancels ~2.5% or ~10% of the vehicle's momentum;
            // anything else is a zombie strike.
            Vector3f probe = impulseProbe;
            vehicle.getLinearVelocity(probe);
            probe.mul(-0.025F * vehicle.getFudgedMass());
            boolean isFoliage = probe.sub(impulse).lengthSquared() < 0.001F;
            vehicle.getLinearVelocity(probe);
            probe.mul(-0.1F * vehicle.getFudgedMass());
            isFoliage = isFoliage || probe.sub(impulse).lengthSquared() < 0.001F;
            if (isFoliage) {
               impulse.mul(massSoften * massScaler * sandbox("BetterVehicleDynamics.ShoveFoliage", 1.0F));
            } else {
               impulse.mul(massSoften * massScaler * sandbox("BetterVehicleDynamics.ShoveZombies", 1.0F));
            }
         }

         Object squishArray = squishImpulseArray.get(vehicle);
         int squishCount = Array.getLength(squishArray);
         float cooldown = corpseCooldown.getOrDefault((int)vehicle.vehicleId, 0.0F);
         cooldown = Math.max(0.0F, cooldown - 0.01F);
         for (int idx = 0; idx < squishCount; idx++) {
            Object entry = Array.get(squishArray, idx);
            if (entry == null || !impulseEnabled.getBoolean(entry)) {
               continue;
            }
            Vector3f impulse = (Vector3f)impulseVector.get(entry);
            if (cooldown < 0.01F) {
               impulse.mul(massSoften * 2.0F * massScaler * sandbox("BetterVehicleDynamics.ShoveCorpses", 1.0F));
               cooldown = 0.08F;
            } else {
               impulse.mul(0.0F);
            }
         }
         corpseCooldown.put((int)vehicle.vehicleId, cooldown);
      } catch (IllegalAccessException denied) {
         throw new RuntimeException("BetterVehicleDynamics: impulse field access denied", denied);
      }
   }

   public static void beforeUpdate(WorldSimulation ws) {
      if (Hooks.enabled && ws.created) {
         pruneSkidMarksWorld();
      }
   }

   // World-tick tyre-mark expiry: every ~2 s, drop BVD tyre marks older than
   // the configured window from every loaded chunk, so they vanish even while
   // the player is on foot. Blood is never touched.
   private static void pruneSkidMarksWorld() {
      long nowMs = System.currentTimeMillis();
      if (nowMs - skidPruneMs < 2000L) {
         return;
      }
      skidPruneMs = nowMs;
      if (IsoWorld.instance == null || IsoWorld.instance.currentCell == null) {
         return;
      }
      IsoChunkMap cm = IsoWorld.instance.currentCell.chunkMap[0];
      if (cm == null) {
         return;
      }
      float worldAge = (float)GameTime.getInstance().getWorldAgeHours();
      int gw = IsoChunkMap.chunkGridWidth;
      for (int cmx = 0; cmx < gw; cmx++) {
         for (int cmy = 0; cmy < gw; cmy++) {
            IsoChunk ch = cm.getChunk(cmx, cmy);
            if (ch != null && ch.floorBloodSplats.size() > 0) {
               Splat.pruneChunk(ch, worldAge);
            }
         }
      }
   }
}
