package bvd.zb;

import java.lang.reflect.Field;
import java.util.ArrayList;
import java.util.Arrays;
import zombie.debug.DebugLog;
import zombie.iso.IsoChunk;
import zombie.iso.IsoChunkMap;
import zombie.iso.IsoFloorBloodSplat;

// BVD tyre marks are floor splats of four extra types appended after
// vanilla's blood types. The manual install extends IsoFloorBloodSplat's
// FLOOR_BLOOD_TYPES in source; under ZombieBuddy the array is swapped for an
// extended copy at load, before any renderer has sized its per-type lists.
public final class Splat {
   public static final int TIREMARK_TYPE_V = 21;
   public static final int TIREMARK_TYPE_H = 22;
   public static final int TIREMARK_TYPE_D1 = 23;
   public static final int TIREMARK_TYPE_D2 = 24;
   public static final int TIREMARK_TYPE_MIN = 21;
   public static final int TIREMARK_TYPE_MAX = 24;
   // Tyre marks vanish much faster than blood: 10 in-game minutes.
   public static final float TIREMARK_FADE_HOURS = 10.0F / 60.0F;

   private static final String[] TIREMARK_SPRITES = {"bvd_tiremark_v", "bvd_tiremark_h", "bvd_tiremark_d1", "bvd_tiremark_d2"};

   private Splat() {
   }

   // Returns false (tyre marks will not render) if the array cannot be
   // extended; driving is unaffected either way.
   static boolean install() {
      String[] types = IsoFloorBloodSplat.FLOOR_BLOOD_TYPES;
      if (types.length > TIREMARK_TYPE_MIN && types[TIREMARK_TYPE_MIN].equals(TIREMARK_SPRITES[0])) {
         return true;
      }
      if (types.length != TIREMARK_TYPE_MIN) {
         DebugLog.log("[BetterVehicleDynamics] vanilla has " + types.length + " floor splat types (expected " + TIREMARK_TYPE_MIN + "); tyre marks disabled.");
         return false;
      }
      String[] extended = Arrays.copyOf(types, TIREMARK_TYPE_MAX + 1);
      System.arraycopy(TIREMARK_SPRITES, 0, extended, TIREMARK_TYPE_MIN, TIREMARK_SPRITES.length);
      try {
         Field f = IsoFloorBloodSplat.class.getField("FLOOR_BLOOD_TYPES");
         Field uf = Class.forName("sun.misc.Unsafe").getDeclaredField("theUnsafe");
         uf.setAccessible(true);
         sun.misc.Unsafe unsafe = (sun.misc.Unsafe)uf.get(null);
         unsafe.putObjectVolatile(unsafe.staticFieldBase(f), unsafe.staticFieldOffset(f), extended);
      } catch (Throwable t) {
         DebugLog.log("[BetterVehicleDynamics] could not register tyre-mark sprites (" + t + "); tyre marks disabled.");
         return false;
      }
      if (IsoFloorBloodSplat.FLOOR_BLOOD_TYPES.length != extended.length) {
         DebugLog.log("[BetterVehicleDynamics] tyre-mark sprite registration did not take; tyre marks disabled.");
         return false;
      }
      padLegacyRenderer(extended.length);
      return true;
   }

   // IsoChunkMap (the legacy, non-FBO renderer) sized its per-type list in its
   // static initialiser; grow it so that renderer can index the new types.
   @SuppressWarnings("unchecked")
   private static void padLegacyRenderer(int count) {
      try {
         Field f = IsoChunkMap.class.getDeclaredField("splatByType");
         f.setAccessible(true);
         ArrayList<ArrayList<IsoFloorBloodSplat>> lists = (ArrayList<ArrayList<IsoFloorBloodSplat>>)f.get(null);
         while (lists.size() < count) {
            lists.add(new ArrayList<>());
         }
      } catch (ReflectiveOperationException | RuntimeException e) {
         DebugLog.log("[BetterVehicleDynamics] legacy renderer not padded (" + e + "); only matters with the old renderer enabled.");
      }
   }

   // Drop BVD tyre marks older than the fade window from one chunk, rebuilding
   // its bounded splat queue, and refresh the chunk's cached floor texture.
   static void pruneChunk(IsoChunk ch, float worldAge) {
      ArrayList<IsoFloorBloodSplat> keep = null;
      int count = ch.floorBloodSplats.size();
      for (int i = 0; i < count; i++) {
         IsoFloorBloodSplat s = ch.floorBloodSplats.get(i);
         boolean expire = s.type >= TIREMARK_TYPE_MIN && s.type <= TIREMARK_TYPE_MAX && worldAge - s.worldAge >= TIREMARK_FADE_HOURS;
         if (expire) {
            if (keep == null) {
               keep = new ArrayList<>();
               for (int k = 0; k < i; k++) {
                  keep.add(ch.floorBloodSplats.get(k));
               }
            }
            ch.floorBloodSplatsFade.remove(s);
         } else if (keep != null) {
            keep.add(s);
         }
      }
      if (keep != null) {
         ch.floorBloodSplats.clear();
         for (int i = 0; i < keep.size(); i++) {
            ch.floorBloodSplats.add(keep.get(i));
         }
         ch.invalidateRenderChunkLevels(1L);
      }
   }
}
