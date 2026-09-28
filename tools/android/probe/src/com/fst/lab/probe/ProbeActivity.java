package com.fst.lab.probe;

import android.app.Activity;
import android.graphics.Rect;
import android.os.Bundle;
import android.util.Log;
import android.widget.TextView;

import java.lang.reflect.InvocationHandler;
import java.lang.reflect.Method;
import java.lang.reflect.Proxy;
import java.util.List;

/**
 * Device-lab probe that reports what Jetpack WindowManager would see.
 *
 * <p>Registers directly with the device's {@code androidx.window.extensions}
 * shared library (the OEM layer Jetpack WindowManager wraps) via reflection,
 * so it needs no Gradle, AndroidX or Maven dependencies. Every window-layout
 * update is logged to logcat under tag {@code FST_PROBE} as one line:
 * {@code window=<w>x<h> features=[fold|hinge state=flat|half bounds=l,t,r,b; ...]}.
 * {@code tools/android/device.py features} installs, launches and parses it.
 */
public class ProbeActivity extends Activity {
    // region Constants

    /** Logcat tag parsed by {@code device.py features}. */
    private static final String TAG = "FST_PROBE";

    // endregion

    // region Lifecycle

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        TextView view = new TextView(this);
        view.setText("FST WindowManager probe");
        setContentView(view);
        try {
            register();
        } catch (Throwable error) {
            Log.i(TAG, "error=" + error);
        }
    }

    // endregion

    // region Extensions

    /**
     * Subscribes to window-layout info through the extensions library.
     *
     * @throws Exception when the library or listener API is unavailable.
     */
    private void register() throws Exception {
        Class<?> provider = Class.forName("androidx.window.extensions.WindowExtensionsProvider");
        Object extensions = provider.getMethod("getWindowExtensions").invoke(null);
        int level = (int) extensions.getClass().getMethod("getVendorApiLevel").invoke(extensions);
        Object component = extensions.getClass().getMethod("getWindowLayoutComponent").invoke(extensions);
        Method chosen = null;
        for (Method method : component.getClass().getMethods()) {
            Class<?>[] params = method.getParameterTypes();
            if (!method.getName().equals("addWindowLayoutInfoListener") || params.length != 2
                    || !params[0].isAssignableFrom(Activity.class) || !params[1].isInterface()) {
                continue;
            }
            // Prefer the extensions-core Consumer (vendor API level 2+).
            if (chosen == null || params[1].getName().startsWith("androidx.window.extensions.core")) {
                chosen = method;
            }
        }
        if (chosen == null) {
            Log.i(TAG, "error=no addWindowLayoutInfoListener (vendor level " + level + ")");
            return;
        }
        Class<?> consumerType = chosen.getParameterTypes()[1];
        InvocationHandler handler = (proxy, method, args) -> {
            switch (method.getName()) {
                case "accept":
                    report(args[0]);
                    return null;
                case "hashCode":
                    return System.identityHashCode(proxy);
                case "equals":
                    return proxy == args[0];
                default:
                    return "FstProbeConsumer";
            }
        };
        Object consumer = Proxy.newProxyInstance(consumerType.getClassLoader(),
                new Class<?>[] {consumerType}, handler);
        Log.i(TAG, "registered vendorApiLevel=" + level + " consumer=" + consumerType.getName());
        chosen.invoke(component, this, consumer);
    }

    /**
     * Logs one window-layout update.
     *
     * @param info an {@code androidx.window.extensions.layout.WindowLayoutInfo}.
     * @throws Exception on reflection failure.
     */
    private void report(Object info) throws Exception {
        List<?> features = (List<?>) info.getClass().getMethod("getDisplayFeatures").invoke(info);
        StringBuilder line = new StringBuilder();
        Rect window = getWindowManager().getCurrentWindowMetrics().getBounds();
        line.append("window=").append(window.width()).append('x').append(window.height());
        line.append(" features=[");
        for (int i = 0; i < features.size(); i++) {
            Object feature = features.get(i);
            Rect bounds = (Rect) feature.getClass().getMethod("getBounds").invoke(feature);
            int type = (int) feature.getClass().getMethod("getType").invoke(feature);
            int state = (int) feature.getClass().getMethod("getState").invoke(feature);
            if (i > 0) {
                line.append("; ");
            }
            line.append(type == 1 ? "fold" : type == 2 ? "hinge" : "type" + type)
                    .append(" state=").append(state == 1 ? "flat" : state == 2 ? "half" : "s" + state)
                    .append(" bounds=").append(bounds.left).append(',').append(bounds.top)
                    .append(',').append(bounds.right).append(',').append(bounds.bottom);
        }
        line.append(']');
        Log.i(TAG, line.toString());
    }

    // endregion
}
