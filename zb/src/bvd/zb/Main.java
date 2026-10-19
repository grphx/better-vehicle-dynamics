package bvd.zb;

import zombie.core.physics.CarController;
import zombie.debug.DebugLog;

// ZombieBuddy entry point. ZombieBuddy only loads this jar when it is
// installed and Better Vehicle Dynamics is enabled; without ZombieBuddy the
// mod.info keys naming it are ignored and the game never sees this code.
public class Main {
   public static void main(String[] args) {
      // A manual install replaces CarController outright; its class carries
      // BVD's bridge method. Hooking that class again would run BVD twice.
      if (hasDeclaredMethod(CarController.class, "bvdBridge")) {
         DebugLog.log("[BetterVehicleDynamics] manual install detected; the ZombieBuddy layer stays off and the manual install drives.");
         return;
      }
      try {
         Hooks.init();
      } catch (Throwable t) {
         DebugLog.log("[BetterVehicleDynamics] this game version does not match the ZombieBuddy layer (" + t + "); driving stays vanilla.");
         return;
      }
      boolean marks = Splat.install();
      Hooks.enabled = true;
      DebugLog.log("[BetterVehicleDynamics] ZombieBuddy layer active" + (marks ? "." : " (tyre marks off)."));
   }

   private static boolean hasDeclaredMethod(Class<?> c, String name) {
      for (java.lang.reflect.Method m : c.getDeclaredMethods()) {
         if (m.getName().equals(name)) {
            return true;
         }
      }
      return false;
   }
}
