package bvd.zb;

import java.lang.invoke.MethodHandle;
import java.lang.invoke.MethodHandles;
import java.lang.invoke.MethodType;
import java.lang.invoke.VarHandle;
import java.util.WeakHashMap;
import zombie.core.physics.CarController;
import zombie.debug.DebugLog;

// Glue between the ZombieBuddy advice in Patches and BVD's drivetrain in
// BvdCar. Every hooked CarController call lands here: when BVD is active the
// call runs on the vehicle's BvdCar and vanilla's body is skipped; otherwise
// (manual install present, or BVD failed) the method returns false and
// vanilla runs untouched.
public final class Hooks {
   static volatile boolean enabled = false;

   private static final WeakHashMap<CarController, BvdCar> cars = new WeakHashMap<>();

   // Vanilla private fields that unhooked vanilla code reads back
   // (isGas()/isGasR()/isBreak()/isGasPedalPressed()/debug()).
   private static VarHandle vIsGas;
   private static VarHandle vIsGasR;
   private static VarHandle vIsBreak;
   private static VarHandle vSteering;
   private static MethodHandle vShouldBeActive;

   private Hooks() {
   }

   static void init() throws ReflectiveOperationException {
      MethodHandles.Lookup l = MethodHandles.privateLookupIn(CarController.class, MethodHandles.lookup());
      vIsGas = l.findVarHandle(CarController.class, "isGas", boolean.class);
      vIsGasR = l.findVarHandle(CarController.class, "isGasR", boolean.class);
      vIsBreak = l.findVarHandle(CarController.class, "isBreak", boolean.class);
      vSteering = l.findVarHandle(CarController.class, "vehicleSteering", float.class);
      vShouldBeActive = l.findVirtual(CarController.class, "shouldBeActive", MethodType.methodType(boolean.class));
   }

   private static BvdCar car(CarController cc) {
      BvdCar car = cars.get(cc);
      if (car == null) {
         car = new BvdCar(cc);
         cars.put(cc, car);
      }
      return car;
   }

   private static void push(BvdCar car) {
      vIsGas.set(car.cc, car.isGas);
      vIsGasR.set(car.cc, car.isGasR);
      vIsBreak.set(car.cc, car.isBreak);
      vSteering.set(car.cc, car.getVehicleSteering());
   }

   // One bad tick must not take the game down with it: log once, hand every
   // vehicle back to vanilla and keep running.
   private static void fail(String where, Throwable t) {
      enabled = false;
      DebugLog.log("[BetterVehicleDynamics] ZombieBuddy layer disabled after an error in " + where + "; driving is vanilla until restart.");
      DebugLog.log("[BetterVehicleDynamics] " + t);
      for (StackTraceElement e : t.getStackTrace()) {
         DebugLog.log("    at " + e);
      }
   }

   public static void attach(CarController cc) {
      if (!enabled) {
         return;
      }
      try {
         car(cc);
      } catch (Throwable t) {
         fail("attach", t);
      }
   }

   public static boolean update(CarController cc) {
      if (!enabled) {
         return false;
      }
      try {
         BvdCar car = car(cc);
         car.update();
         push(car);
      } catch (Throwable t) {
         fail("update", t);
      }
      return true;
   }

   public static boolean updateTrailer(CarController cc) {
      if (!enabled) {
         return false;
      }
      try {
         BvdCar car = car(cc);
         car.updateTrailer();
         push(car);
      } catch (Throwable t) {
         fail("updateTrailer", t);
      }
      return true;
   }

   public static void updateControls(CarController cc) {
      if (!enabled) {
         return;
      }
      try {
         car(cc).readPedals();
      } catch (Throwable t) {
         fail("updateControls", t);
      }
   }

   public static boolean park(CarController cc) {
      if (!enabled) {
         return false;
      }
      try {
         BvdCar car = car(cc);
         car.park();
         push(car);
      } catch (Throwable t) {
         fail("park", t);
      }
      return true;
   }

   public static boolean noControl(CarController cc) {
      if (!enabled) {
         return false;
      }
      try {
         BvdCar car = car(cc);
         car.control_NoControl();
         push(car);
      } catch (Throwable t) {
         fail("control_NoControl", t);
      }
      return true;
   }

   public static boolean checkShouldBeActive(CarController cc) {
      if (!enabled) {
         return false;
      }
      try {
         car(cc).checkShouldBeActive();
      } catch (Throwable t) {
         fail("checkShouldBeActive", t);
      }
      return true;
   }

   // A towing vehicle's activity, asked by the vehicle it tows: answered by
   // its own BvdCar when it has one, else by vanilla.
   static boolean shouldBeActive(CarController cc) {
      BvdCar car = cars.get(cc);
      if (car != null) {
         return car.shouldBeActive();
      }
      try {
         return (boolean)vShouldBeActive.invokeExact(cc);
      } catch (Throwable t) {
         throw new IllegalStateException(t);
      }
   }

   public static float steering(CarController cc, float vanilla) {
      if (!enabled) {
         return vanilla;
      }
      BvdCar car = cars.get(cc);
      return car == null ? vanilla : car.getVehicleSteering();
   }
}
