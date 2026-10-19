package bvd.zb;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.core.physics.CarController;
import zombie.core.physics.WorldSimulation;

// ZombieBuddy advice. Each body is inlined into the vanilla method, so it only
// calls public statics; all logic lives in Hooks / BvdWorld.
public class Patches {
   @Patch(className = "zombie.core.physics.CarController", methodName = "<init>")
   public static class CarInit {
      @Patch.OnExit
      public static void exit(@Patch.This CarController self) {
         Hooks.attach(self);
      }
   }

   @Patch(className = "zombie.core.physics.CarController", methodName = "update")
   public static class CarUpdate {
      @Patch.OnEnter(skipOn = true)
      public static boolean enter(@Patch.This CarController self) {
         return Hooks.update(self);
      }
   }

   @Patch(className = "zombie.core.physics.CarController", methodName = "updateTrailer")
   public static class CarUpdateTrailer {
      @Patch.OnEnter(skipOn = true)
      public static boolean enter(@Patch.This CarController self) {
         return Hooks.updateTrailer(self);
      }
   }

   // Not skipped: vanilla's updateControls fills clientControls exactly as
   // BVD's does, and other mods hook it too. BVD only adds its pedal reads.
   @Patch(className = "zombie.core.physics.CarController", methodName = "updateControls")
   public static class CarUpdateControls {
      @Patch.OnExit
      public static void exit(@Patch.This CarController self) {
         Hooks.updateControls(self);
      }
   }

   @Patch(className = "zombie.core.physics.CarController", methodName = "park")
   public static class CarPark {
      @Patch.OnEnter(skipOn = true)
      public static boolean enter(@Patch.This CarController self) {
         return Hooks.park(self);
      }
   }

   @Patch(className = "zombie.core.physics.CarController", methodName = "control_NoControl")
   public static class CarNoControl {
      @Patch.OnEnter(skipOn = true)
      public static boolean enter(@Patch.This CarController self) {
         return Hooks.noControl(self);
      }
   }

   @Patch(className = "zombie.core.physics.CarController", methodName = "checkShouldBeActive")
   public static class CarCheckShouldBeActive {
      @Patch.OnEnter(skipOn = true)
      public static boolean enter(@Patch.This CarController self) {
         return Hooks.checkShouldBeActive(self);
      }
   }

   @Patch(className = "zombie.core.physics.CarController", methodName = "getVehicleSteering")
   public static class CarSteering {
      @Patch.OnExit
      public static void exit(@Patch.This CarController self, @Patch.Return(readOnly = false) float steering) {
         steering = Hooks.steering(self, steering);
      }
   }

   @Patch(className = "zombie.core.physics.WorldSimulation", methodName = "create")
   public static class WorldCreate {
      @Patch.OnEnter
      public static void enter(@Patch.This WorldSimulation self) {
         BvdWorld.beforeCreate(self);
      }
   }

   @Patch(className = "zombie.core.physics.WorldSimulation", methodName = "updatePhysic")
   public static class WorldUpdatePhysic {
      @Patch.OnEnter
      public static void enter() {
         BvdWorld.beforePhysicsFrame();
      }
   }

   // Runs once per 0.01 s physics substep, right before Bullet steps.
   @Patch(className = "zombie.core.physics.WorldSimulation", methodName = "updateVehiclePhysics")
   public static class WorldVehicleSubstep {
      @Patch.OnEnter(skipOn = true)
      public static boolean enter() {
         return BvdWorld.vehicleSubstep();
      }
   }

   @Patch(className = "zombie.core.physics.WorldSimulation", methodName = "updateInternal")
   public static class WorldUpdateInternal {
      @Patch.OnEnter
      public static void enter(@Patch.This WorldSimulation self) {
         BvdWorld.beforeUpdate(self);
      }
   }
}
