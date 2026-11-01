import java.io.*;
import java.lang.reflect.*;
import java.nio.file.*;
import java.nio.charset.*;
import java.util.*;
public class KahluaValidation {
  public static void main(String[] args) throws Exception {
    Class<?> pc = Class.forName("se.krka.kahlua.j2se.J2SEPlatform");
    Object platform = pc.newInstance();
    Object env = pc.getMethod("newEnvironment").invoke(platform);
    Class<?> platformInterface = Class.forName("se.krka.kahlua.vm.Platform");
    Class<?> tableInterface = Class.forName("se.krka.kahlua.vm.KahluaTable");
    Class<?> tc = Class.forName("se.krka.kahlua.vm.KahluaThread");
    Object thread = tc.getConstructor(platformInterface, tableInterface).newInstance(platform, env);
    tc.getField("debugOwnerThread").set(thread, Thread.currentThread());
    Class<?> cc = Class.forName("se.krka.kahlua.luaj.compiler.LuaCompiler");
    Method load = cc.getMethod("loadstring", String.class, String.class, tableInterface);
    Method call = tc.getMethod("pcall", Object.class, Object[].class);
    for (String name : args) {
      String source = new String(Files.readAllBytes(Paths.get(name)), StandardCharsets.UTF_8);
      Object closure = load.invoke(null, source, name, env);
      Object[] result = (Object[])call.invoke(thread, closure, new Object[0]);
      System.out.println(name + ": " + Arrays.toString(result));
      if (!Boolean.TRUE.equals(result[0])) throw new RuntimeException("Lua validation failed: " + Arrays.toString(result));
    }
  }
}
