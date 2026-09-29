package com.thehyaline.piliplus;

import android.annotation.SuppressLint;
import android.app.Activity;
import android.app.PendingIntent;
import android.app.PictureInPictureParams;
import android.app.RemoteAction;
import android.app.SearchManager;
import android.app.UiModeManager;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.content.pm.ShortcutInfo;
import android.content.pm.ShortcutManager;
import android.content.res.Configuration;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Point;
import android.graphics.Rect;
import android.graphics.Typeface;
import android.graphics.drawable.Icon;
import android.hardware.display.DisplayManager;
import android.media.session.PlaybackState;
import android.net.Uri;
import android.os.Build;
import android.provider.MediaStore;
import android.provider.Settings;
import android.util.Rational;
import android.view.Display;
import android.view.WindowManager;

import androidx.annotation.DrawableRes;
import androidx.annotation.Keep;
import androidx.annotation.NonNull;
import androidx.annotation.RequiresApi;

import com.github.dart_lang.jni_flutter.JniFlutterPlugin;

import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.Map;
import java.util.Objects;

@Keep
public final class AndroidHelper {
    public static final boolean isFoldable;

    public static final boolean isPipAvailable;

    /** 电视 / 电视盒子（Dart 侧入口是 {@code DeviceUtils.isTv}）。 */
    public static final boolean isTelevision;

    public static volatile boolean isPipMode = false;

    static {
        Context context = getContext();
        PackageManager pm = context.getPackageManager();
        isFoldable = Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && pm.hasSystemFeature(PackageManager.FEATURE_SENSOR_HINGE_ANGLE);
        isPipAvailable = pm.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE);
        isTelevision = isTelevisionDevice(context, pm);
    }

    /**
     * 电视判定，三条任一成立即算：系统按电视 UI 模式跑、声明了 leanback 特性
     * （认证过的 Android TV 必有）、声明了电视设备类型特性。
     *
     * 兜底是"没有触摸屏"：手机和平板一定有触摸屏，没有触摸屏的 Android 只剩
     * 电视、盒子和车机这类固定横屏的大屏设备（非触屏 Chromebook 也算在内，
     * 对它们"横屏 + 宽布局"同样成立），它们全都该按电视处理。
     *
     * 反过来不能拿屏幕尺寸猜：电视的逻辑短边只有 540dp（1080p@xhdpi 是 960x540），
     * 够不到 600dp 那条平板门槛，"够不够大"判不出电视。
     */
    private static boolean isTelevisionDevice(Context context, PackageManager pm) {
        try {
            UiModeManager uiModeManager = (UiModeManager) context.getSystemService(Context.UI_MODE_SERVICE);
            if (uiModeManager != null
                    && uiModeManager.getCurrentModeType() == Configuration.UI_MODE_TYPE_TELEVISION) {
                return true;
            }
        } catch (Exception ignored) {
        }
        if (pm.hasSystemFeature(PackageManager.FEATURE_LEANBACK)
                || pm.hasSystemFeature("android.hardware.type.television")) {
            return true;
        }
        return !pm.hasSystemFeature(PackageManager.FEATURE_TOUCHSCREEN)
                && !pm.hasSystemFeature(PackageManager.FEATURE_FAKETOUCH);
    }

    private AndroidHelper() {
    }

    private static Context getContext() {
        return JniFlutterPlugin.getApplicationContext();
    }

    public static int sdkInt() {
        return Build.VERSION.SDK_INT;
    }

    public static void back() {
        Intent intent = new Intent(Intent.ACTION_MAIN);
        intent.addCategory(Intent.CATEGORY_HOME);
        intent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        getContext().startActivity(intent);
    }

    public static void biliSendCommAntifraud(
            int action, long oid, int type, long rpId, long root, long parent, long ctime, @NonNull String commentText,
            String pictures, @NonNull String sourceId, long uid, @NonNull String cookie
    ) {
        Intent intent = new Intent();
        intent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        intent.setComponent(new ComponentName(
                "icu.freedomIntrovert.biliSendCommAntifraud",
                "icu.freedomIntrovert.biliSendCommAntifraud.ByXposedLaunchedActivity"
        ));
        intent.putExtra("action", action);
        intent.putExtra("oid", oid);
        intent.putExtra("type", type);
        intent.putExtra("rpid", rpId);
        intent.putExtra("root", root);
        intent.putExtra("parent", parent);
        intent.putExtra("ctime", ctime);
        intent.putExtra("comment_text", commentText);
        if (pictures != null) {
            intent.putExtra("pictures", pictures);
        }
        intent.putExtra("source_id", sourceId);
        intent.putExtra("uid", uid);
        ArrayList<String> cookiesList = new ArrayList<>(1);
        cookiesList.add(cookie);
        intent.putStringArrayListExtra("cookies", cookiesList);
        getContext().startActivity(intent);
    }

    public static void openLinkVerifySettings() {
        Context context = getContext();
        Uri uri = Uri.parse("package:" + context.getPackageName());
        try {
            Intent intent;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                intent = new Intent(Settings.ACTION_APP_OPEN_BY_DEFAULT_SETTINGS, uri);
            } else {
                intent = new Intent(Intent.ACTION_MAIN, uri);
                intent.setClassName(
                        "com.android.settings",
                        "com.android.settings.applications.InstalledAppOpenByDefaultActivity"
                );
            }
            intent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            context.startActivity(intent);
        } catch (Exception ignored) {
            Intent intent = new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, uri);
            intent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            context.startActivity(intent);
        }
    }

    public static boolean openMusic(@NonNull String title, String artist, String album) {
        Intent intent = new Intent(MediaStore.INTENT_ACTION_MEDIA_SEARCH);
        intent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        intent.putExtra(SearchManager.QUERY, title);
        intent.putExtra(MediaStore.EXTRA_MEDIA_TITLE, title);
        if (artist != null) {
            intent.putExtra(MediaStore.EXTRA_MEDIA_ARTIST, artist);
        }
        if (album != null) {
            intent.putExtra(MediaStore.EXTRA_MEDIA_ALBUM, album);
        }
        intent.addCategory(Intent.CATEGORY_DEFAULT);

        Context context = getContext();
        PackageManager pm = context.getPackageManager();

        try {
            if (pm.resolveActivity(intent, PackageManager.MATCH_DEFAULT_ONLY) != null) {
                context.startActivity(intent);
                return true;
            }
        } catch (Exception ignored) {
        }

        try {
            intent.setAction(MediaStore.INTENT_ACTION_MEDIA_PLAY_FROM_SEARCH);
            if (pm.resolveActivity(intent, PackageManager.MATCH_DEFAULT_ONLY) != null) {
                context.startActivity(intent);
                return true;
            }
        } catch (Exception ignored) {
        }

        return false;
    }

    public static void enterPip(long engineId, int width, int height, boolean autoEnter, boolean isLive, boolean isPlaying) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Activity activity = JniFlutterPlugin.getActivity(engineId);
            assert activity != null;
            PictureInPictureParams.Builder builder = new PictureInPictureParams.Builder()
                    .setAspectRatio(new Rational(width, height));
            setPipActions(activity, builder, isLive, isPlaying);
            if (autoEnter) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    builder.setAutoEnterEnabled(true);
                    activity.setPictureInPictureParams(builder.build());
                }
            } else {
                activity.enterPictureInPictureMode(builder.build());
            }
        }
    }

    @RequiresApi(api = Build.VERSION_CODES.O)
    public static void updatePipActions(long engineId, boolean isLive, boolean isPlaying) {
        Activity activity = JniFlutterPlugin.getActivity(engineId);
        assert activity != null;
        PictureInPictureParams.Builder builder = new PictureInPictureParams.Builder();
        setPipActions(activity, builder, isLive, isPlaying);
        activity.setPictureInPictureParams(builder.build());
    }

    @RequiresApi(api = Build.VERSION_CODES.O)
    private static void setPipActions(Activity activity, PictureInPictureParams.Builder builder, boolean isLive, boolean isPlaying) {
        ComponentName mbrComponent = MediaHelper.getMediaButtonReceiverComponent(activity);
        if (mbrComponent == null) return;
        ArrayList<RemoteAction> actionList = new ArrayList<>(3);
        if (!isLive) {
            actionList.add(getRemoteAction(mbrComponent, activity, R.drawable.ic_player_rewind_10s, "ACTION_REWIND", (int) PlaybackState.ACTION_REWIND));
        }
        if (isPlaying) {
            actionList.add(getRemoteAction(mbrComponent, activity, R.drawable.ic_player_pause, "ACTION_PAUSE", (int) PlaybackState.ACTION_PAUSE));
        } else {
            actionList.add(getRemoteAction(mbrComponent, activity, R.drawable.ic_player_play, "ACTION_PLAY", (int) PlaybackState.ACTION_PLAY));
        }
        if (!isLive) {
            actionList.add(getRemoteAction(mbrComponent, activity, R.drawable.ic_player_fast_forward_10s, "ACTION_FAST_FORWARD", (int) PlaybackState.ACTION_FAST_FORWARD));
        }
        builder.setActions(actionList);
    }

    @RequiresApi(api = Build.VERSION_CODES.O)
    private static RemoteAction getRemoteAction(@NonNull ComponentName mbrComponent, Activity activity, @DrawableRes int resId, String title, int action) {
        return new RemoteAction(
                Icon.createWithResource(activity, resId),
                title,
                title,
                Objects.requireNonNull(MediaHelper.buildMediaButtonPendingIntent(activity, mbrComponent, action))
        );
    }

    public static void disableAutoEnterPip(long engineId) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            Activity activity = JniFlutterPlugin.getActivity(engineId);
            if (activity != null) {
                activity.setPictureInPictureParams(new PictureInPictureParams.Builder()
                        .setAutoEnterEnabled(false)
                        .build()
                );
            }
        }
    }

    /**
     * 屏幕最大尺寸（dp），用来判断当前窗口是不是被分屏 / 小窗缩过
     * （Dart 侧 {@code MaxScreenSize.isWindowMode}）。
     *
     * 顺序不保证：调用方宽高两个方向都拿这个值比，所以不用补旋转。
     */
    public static int[] maxScreenSize() {
        Context context = getContext();
        try {
            final Point maxSize = new Point();
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                Rect maxBounds = context.getSystemService(WindowManager.class)
                        .getMaximumWindowMetrics()
                        .getBounds();
                maxSize.set(maxBounds.width(), maxBounds.height());
            } else {
                // R 以下没有 WindowMetrics，Display 那批尺寸方法（getRealSize 等）在
                // API 30 全废弃了，剩下的非废弃接口只有 display mode：它给的是面板原生
                // 分辨率，不随旋转变，而调用方两个方向都比，正好不用补旋转。
                Display display = context.getSystemService(DisplayManager.class)
                        .getDisplay(Display.DEFAULT_DISPLAY);
                if (display == null) {
                    return null;
                }
                Display.Mode mode = display.getMode();
                if (mode == null) {
                    return null;
                }
                maxSize.set(mode.getPhysicalWidth(), mode.getPhysicalHeight());
            }
            float density = context.getResources().getDisplayMetrics().density;
            return new int[]{Math.round(maxSize.x / density), Math.round(maxSize.y / density)};
        } catch (Exception ignored) {
            return null;
        }
    }

    public static void createShortcut(@NonNull String id, @NonNull String uri, @NonNull String label, @NonNull String icon) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Context context = getContext();
            ShortcutManager shortcutManager = context.getSystemService(ShortcutManager.class);
            if (shortcutManager != null && shortcutManager.isRequestPinShortcutSupported()) {
                Bitmap bitmap = BitmapFactory.decodeFile(icon);
                ShortcutInfo shortcut = new ShortcutInfo.Builder(context, id)
                        .setShortLabel(label)
                        .setIcon(Icon.createWithAdaptiveBitmap(bitmap))
                        .setIntent(new Intent(Intent.ACTION_VIEW, Uri.parse(uri)))
                        .build();
                // TODO: WorkerThread
                Intent pinIntent = shortcutManager.createShortcutResultIntent(shortcut);
                PendingIntent pendingIntent = PendingIntent.getBroadcast(
                        context, 0, pinIntent, PendingIntent.FLAG_IMMUTABLE
                );
                shortcutManager.requestPinShortcut(shortcut, pendingIntent.getIntentSender());
            }
        }
    }

    /**
     * 系统字体族名列表；取不到时返回 null（Dart 侧会退回自己的内置列表）。
     *
     * Typeface 至今没有公开的枚举接口，只能反射它的私有字体表；两条路都是隐藏 API，
     * Android 9 起反射会被拦，拦下来就返回 null。
     */
    @SuppressLint("BlockedPrivateApi")
    public static String[] fontFamilies() {
        Object systemFontMap = null;
        try {
            Method method = Typeface.class.getDeclaredMethod("getSystemFontMap");
            method.setAccessible(true);
            systemFontMap = method.invoke(null);
        } catch (Exception ignored) {
            try {
                @SuppressLint("DiscouragedPrivateApi") Field field = Typeface.class.getDeclaredField("sSystemFontMap");
                field.setAccessible(true);
                systemFontMap = field.get(null);
            } catch (Exception ignored0) {
            }
        }
        // 那张表是 Map<String, Typeface>，但泛型运行时已经擦除：直接转成
        // Map<String, Typeface> 会触发 unchecked 警告，真碰上非 String 的键还会在
        // toArray 里炸 ArrayStoreException。按 Map<?, ?> 收下、只挑 String 键，两边都避开。
        if (!(systemFontMap instanceof Map<?, ?> fontMap)) {
            return null;
        }
        return fontMap.keySet().stream()
                .filter(String.class::isInstance)
                .map(String.class::cast)
                .toArray(String[]::new);
    }

    public static void updateDocProvider(boolean enabled) {
        Context context = getContext();
        final ComponentName componentName = new ComponentName(context, BiliDocumentsProvider.class);
        final int state = enabled ? PackageManager.COMPONENT_ENABLED_STATE_ENABLED
                : PackageManager.COMPONENT_ENABLED_STATE_DISABLED;
        context.getPackageManager().setComponentEnabledSetting(componentName, state, PackageManager.DONT_KILL_APP);
    }

    @Keep
    public static final class ToDart {
        public static volatile Runnable onUserLeaveHint;
        public static Runnable onConfigurationChanged;

        private ToDart() {
        }
    }
}
