package bvd.zb;

import java.lang.reflect.Field;
import java.util.HashMap;
import se.krka.kahlua.integration.annotations.LuaMethod;
import zombie.core.textures.Texture;

// Lua globals the ZombieBuddy layer provides in place of the methods the
// manual install adds to vanilla classes.
public class LuaApi {
   private static HashMap<String, Texture> sharedTextures;

   // Same as the manual install's Texture.BVD_registerSharedTexture: put a
   // loaded texture into the shared table under a sprite name, so the tyre
   // mark sprites resolve without a texture pack.
   @LuaMethod(name = "BVD_registerSharedTexture", global = true)
   public static void registerSharedTexture(String name, Texture texture) {
      if (name == null || texture == null) {
         return;
      }
      HashMap<String, Texture> table = sharedTable();
      if (table != null) {
         table.put(name, texture);
      }
   }

   // True when the ZombieBuddy layer is driving (Lua uses it for the install
   // readout).
   @LuaMethod(name = "BVD_zombieBuddyActive", global = true)
   public static boolean zombieBuddyActive() {
      return Hooks.enabled;
   }

   @SuppressWarnings("unchecked")
   private static HashMap<String, Texture> sharedTable() {
      if (sharedTextures == null) {
         try {
            Field f = Texture.class.getDeclaredField("s_sharedTextureTable");
            f.setAccessible(true);
            sharedTextures = (HashMap<String, Texture>)f.get(null);
         } catch (ReflectiveOperationException | RuntimeException e) {
            return null;
         }
      }
      return sharedTextures;
   }
}
