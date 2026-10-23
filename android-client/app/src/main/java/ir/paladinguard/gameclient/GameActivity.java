package ir.paladinguard.gameclient;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.net.Uri;
import android.provider.DocumentsContract;
import android.content.pm.ActivityInfo;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.opengl.GLSurfaceView;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.TextView;

import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.net.SocketTimeoutException;

/** PGRP standalone Android 3D client prototype.
 * No third-party SA-MP Android app is installed or launched.
 * Real open.mp in-game protocol is a separate, unimplemented milestone.
 */
public final class GameActivity extends Activity {
    private static final int GTA_TREE_REQUEST=3019;
    private static final String PREFS="pgrp_gta_local_assets";
    private static final int BACK=0xCC0B1725,WHITE=0xFFF3F5F6,GOLD=0xFFEABB70,CYAN=0xFF59C9EA;
    private GLSurfaceView surface;
    private WorldRenderer renderer;
    private TextView networkStatus,playerCoords;
    private final Handler handler=new Handler(Looper.getMainLooper());
    private final ExecutorService io=Executors.newSingleThreadExecutor();
    private boolean busy;
    private boolean inspectingAssets;
    private TextView assetStatus;

    @Override public void onCreate(Bundle saved) {
        super.onCreate(saved);
        setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE);
        getWindow().getDecorView().setSystemUiVisibility(
            View.SYSTEM_UI_FLAG_FULLSCREEN|View.SYSTEM_UI_FLAG_HIDE_NAVIGATION|
            View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY|View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN|
            View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION|View.SYSTEM_UI_FLAG_LAYOUT_STABLE);
        getWindow().addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);

        FrameLayout root=new FrameLayout(this);
        root.setBackgroundColor(Color.rgb(6,13,21));
        surface=new GLSurfaceView(this);
        surface.setEGLContextClientVersion(2);
        surface.setPreserveEGLContextOnPause(true);
        renderer=new WorldRenderer((x,z,yaw)->handler.post(()->{
            if(playerCoords!=null)
                playerCoords.setText(String.format(Locale.US,"X %.0f     Z %.0f     HDG %.0f°",
                    x,z,Math.toDegrees(yaw)));
        }));
        surface.setRenderer(renderer);
        surface.setRenderMode(GLSurfaceView.RENDERMODE_CONTINUOUSLY);
        root.addView(surface,new FrameLayout.LayoutParams(-1,-1));

        TouchControls controls=new TouchControls(this,renderer);
        root.addView(controls,new FrameLayout.LayoutParams(-1,-1));

        LinearLayout hud=new LinearLayout(this);
        hud.setGravity(Gravity.CENTER_VERTICAL);
        hud.setOrientation(LinearLayout.HORIZONTAL);
        hud.setPadding(dp(16),dp(10),dp(13),dp(10));
        hud.setBackground(bg(BACK,0,0));
        FrameLayout.LayoutParams hp=new FrameLayout.LayoutParams(-1,dp(70),Gravity.TOP);
        root.addView(hud,hp);

        LinearLayout title=new LinearLayout(this);title.setOrientation(LinearLayout.VERTICAL);
        TextView logo=label("PALADIN GUARD  /  ROLEPLAY",17,GOLD,true);
        logo.setLetterSpacing(.09f);
        title.addView(logo);
        TextView sub=label("ANDROID NATIVE GAME CLIENT  •  ALPHA 0.3",10,CYAN,true);
        title.addView(sub);
        hud.addView(title,new LinearLayout.LayoutParams(0,-2,1));

        networkStatus=label("سرور بررسی نشده",12,WHITE,false);
        networkStatus.setPadding(dp(8),0,dp(8),0);
        hud.addView(networkStatus);

        Button probe=smallButton("تست اتصال",GOLD,0xFF0E1A28);
        probe.setOnClickListener(v->checkNetwork());
        hud.addView(probe);

        Button reset=smallButton("بازگشت به نقطه شروع",0xFF274053,WHITE);
        reset.setOnClickListener(v->renderer.reset());
        LinearLayout.LayoutParams resetLp=new LinearLayout.LayoutParams(-2,dp(42));
        resetLp.leftMargin=dp(8);
        hud.addView(reset,resetLp);

        Button assets=smallButton("دیتای GTA",0xFF254459,GOLD);
        assets.setOnClickListener(v->showDataOptions());
        LinearLayout.LayoutParams assetLp=new LinearLayout.LayoutParams(-2,dp(42));
        assetLp.leftMargin=dp(8);
        hud.addView(assets,assetLp);

        playerCoords=label("X 0     Z 12     HDG 0°",12,WHITE,true);
        playerCoords.setPadding(dp(10),dp(7),dp(10),dp(7));
        playerCoords.setBackground(bg(0xAA0B1725,10,0x4459C9EA));
        FrameLayout.LayoutParams coordLp=new FrameLayout.LayoutParams(-2,-2,Gravity.BOTTOM|Gravity.CENTER_HORIZONTAL);
        coordLp.bottomMargin=dp(14);
        root.addView(playerCoords,coordLp);

        Button action=smallButton("حرکت سریع",0xAA254057,CYAN);
        action.setOnClickListener(v->renderer.sprintStep());
        FrameLayout.LayoutParams act=new FrameLayout.LayoutParams(dp(117),dp(47),Gravity.BOTTOM|Gravity.RIGHT);
        act.rightMargin=dp(24);act.bottomMargin=dp(72);
        root.addView(action,act);

        TextView disclaimer=label("دموی موتور مستقل — محیط آزمایشی؛ هنوز به گیم‌مود open.mp متصل نیست",10,0xFFE5C791,false);
        disclaimer.setGravity(Gravity.CENTER);
        disclaimer.setBackground(bg(0xBB0B1725,7,0));
        FrameLayout.LayoutParams noteLp=new FrameLayout.LayoutParams(-2,dp(27),Gravity.BOTTOM|Gravity.RIGHT);
        noteLp.rightMargin=dp(18);noteLp.bottomMargin=dp(10);
        root.addView(disclaimer,noteLp);

        assetStatus=label("دیتای واقعی GTA هنوز انتخاب نشده",11,GOLD,true);
        assetStatus.setPadding(dp(9),dp(5),dp(9),dp(5));
        assetStatus.setBackground(bg(0xB60B1725,9,0x6659C9EA));
        FrameLayout.LayoutParams assetLabelParams=new FrameLayout.LayoutParams(-2,-2,Gravity.TOP|Gravity.CENTER_HORIZONTAL);
        assetLabelParams.topMargin=dp(79);
        root.addView(assetStatus,assetLabelParams);

        setContentView(root);
        String savedTree=getSharedPreferences(PREFS,MODE_PRIVATE).getString("gta_tree","");
        if(!savedTree.isEmpty()){
            assetStatus.setText("دیتای GTA انتخاب شده — بررسی مجدد در حال اجرا");
            inspectTree(Uri.parse(savedTree));
        }
        handler.postDelayed(()->new AlertDialog.Builder(this)
            .setTitle("PGRP Independent Client — Alpha 0.2")
            .setMessage("این برنامه یک موتور سه‌بعدی مستقل با کنترل لمسی است، نه SA-MP Launcher.\n\n"
                +"شهر فعلی آزمایشی است و هیچ فایل GTA در آن قرار ندارد.\n\n"
                +"برای ورود واقعی به سرور PGRP، بخش پروتکل RakNet/open.mp، ورود/ثبت‌نام، همگام‌سازی بازیکن، مدل‌ها و فیزیک بازی باید تکمیل شود.\n\n"
                +"جوی‌استیک سمت چپ حرکت است؛ سمت راست صفحه دوربین را می‌چرخاند. دکمه تست اتصال وضعیت شبکه را بررسی می‌کند، نه ورود به بازی.")
            .setPositiveButton("شروع آزمایش",(d,w)->{}).show(),350);
    }


    private void showDataOptions(){
        new AlertDialog.Builder(this)
            .setTitle("دیتای واقعی GTA San Andreas")
            .setMessage("برای بررسی فایل‌های واقعی نقشه، پوشه GTA.San.Andreas را از نسخه قانونی کامپیوتر به حافظه گوشی منتقل کن.\\n\\n"
                +"پیشنهاد مسیر گوشی: Download/PGRP-GTA/GTA.San.Andreas\\n"
                +"پوشه‌های data و models باید مستقیماً داخل پوشه GTA.San.Andreas باشند.\\n\\n"
                +"با انتخاب پوشه، PGRP فقط فایل‌های gta.dat و IMG را بررسی می‌کند؛ فایل‌ها آپلود، پاک یا دست‌کاری نمی‌شوند.\\n"
                +"هنوز نمایش نقشه GTA و ورود واقعی به open.mp پشتیبانی نمی‌شود.")
            .setPositiveButton("انتخاب پوشه",(dialog,which)->chooseGameFolder())
            .setNeutralButton("بررسی انتخاب قبلی",(dialog,which)->{
                String stored=getSharedPreferences(PREFS,MODE_PRIVATE).getString("gta_tree","");
                if(stored.isEmpty()){
                    new AlertDialog.Builder(this).setMessage("هنوز پوشه‌ای انتخاب نشده است.")
                        .setPositiveButton("متوجه شدم",null).show();
                }else inspectTree(Uri.parse(stored));
            })
            .setNegativeButton("بستن",null).show();
    }

    private void chooseGameFolder(){
        try{
            Intent intent=new Intent(Intent.ACTION_OPEN_DOCUMENT_TREE);
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION |
                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION |
                Intent.FLAG_GRANT_PREFIX_URI_PERMISSION);
            startActivityForResult(intent,GTA_TREE_REQUEST);
        }catch(Exception e){
            new AlertDialog.Builder(this).setMessage("انتخاب پوشه در نسخه اندروید یا فایل‌منیجر فعلی در دسترس نیست.")
                .setPositiveButton("بستن",null).show();
        }
    }

    @Override protected void onActivityResult(int requestCode,int resultCode,Intent data){
        super.onActivityResult(requestCode,resultCode,data);
        if(requestCode!=GTA_TREE_REQUEST || resultCode!=RESULT_OK || data==null)return;
        Uri tree=data.getData();
        if(tree==null)return;
        try{
            getContentResolver().takePersistableUriPermission(tree,
                Intent.FLAG_GRANT_READ_URI_PERMISSION);
            getSharedPreferences(PREFS,MODE_PRIVATE).edit().putString("gta_tree",tree.toString()).apply();
            inspectTree(tree);
        }catch(Exception e){
            new AlertDialog.Builder(this)
                .setMessage("دسترسی پایدار به پوشه داده نشد. دوباره پوشه را از فایل‌منیجر انتخاب کن.\\n"+e.getMessage())
                .setPositiveButton("بستن",null).show();
        }
    }

    private void inspectTree(Uri tree){
        if(inspectingAssets)return;
        inspectingAssets=true;
        if(assetStatus!=null)assetStatus.setText("در حال بررسی دیتای محلی GTA...");
        io.submit(()->{
            GtaAssetInspector.Report report=null;
            String failed=null;
            try{
                report=new GtaAssetInspector(this,tree).inspect();
            }catch(Exception e){failed=e.getMessage();}
            final GtaAssetInspector.Report checked=report;
            final String error=failed;
            handler.post(()->{
                inspectingAssets=false;
                if(isFinishing()||isDestroyed())return;
                if(checked!=null){
                    assetStatus.setText(checked.readyForIndexing?
                        "دیتای GTA شناسایی شد — "+checked.objects+" مدل در IMG":
                        "دیتای GTA ناقص یا ناسازگار");
                    new AlertDialog.Builder(this)
                        .setTitle(checked.readyForIndexing?"شناسایی موفق دیتای GTA":"بررسی فایل‌های GTA")
                        .setMessage(checked.details)
                        .setPositiveButton("بستن",null).show();
                }else{
                    assetStatus.setText("خواندن پوشه GTA امکان‌پذیر نشد");
                    new AlertDialog.Builder(this)
                        .setMessage("خطا هنگام خواندن داده‌های محلی:\\n"+error)
                        .setPositiveButton("بستن",null).show();
                }
            });
        });
    }

    private int dp(float x){return (int)(x*getResources().getDisplayMetrics().density+.5f);}

    private GradientDrawable bg(int color,int radius,int stroke){
        GradientDrawable d=new GradientDrawable();
        d.setColor(color);d.setCornerRadius(dp(radius));
        if(stroke!=0)d.setStroke(dp(1),stroke);
        return d;
    }
    private TextView label(String value,int size,int color,boolean bold){
        TextView t=new TextView(this);
        t.setText(value);t.setTextSize(size);t.setTextColor(color);
        t.setGravity(Gravity.CENTER_VERTICAL);
        t.setTypeface(Typeface.create(bold?"sans-serif-medium":"sans-serif",
            bold?Typeface.BOLD:Typeface.NORMAL));
        return t;
    }
    private Button smallButton(String value,int fill,int foreground){
        Button b=new Button(this);
        b.setAllCaps(false);b.setText(value);b.setTextSize(12);
        b.setPadding(dp(9),0,dp(9),0);
        b.setMinimumWidth(0);b.setMinimumHeight(0);
        b.setTextColor(foreground);b.setBackground(bg(fill,10,0));
        return b;
    }

    private void checkNetwork(){
        if(busy)return;
        busy=true;
        networkStatus.setText("در حال بررسی...");
        io.submit(()->{
            String status;
            try{
                // Info query does not imply that the multiplayer client is authenticated.
                status=GameNetworkProbe.pingInfo();
            }catch(SocketTimeoutException timeout){
                status="پاسخ وضعیت دریافت نشد";
            }catch(Exception e){
                status="وضعیت سرور نامشخص";
            }
            String stage;
            try{
                stage=GameNetworkProbe.probeRakNetHandshake();
            }catch(SocketTimeoutException timeout){
                stage="پاسخ مرحله اول RakNet دریافت نشد";
            }catch(Exception e){
                stage="RakNet: "+e.getClass().getSimpleName();
            }
            final String line=status;
            final String details=stage;
            handler.post(()->{
                if(isFinishing()||isDestroyed())return;
                busy=false;
                if(networkStatus!=null)networkStatus.setText(line);
                new AlertDialog.Builder(this)
                    .setTitle("وضعیت ارتباط با سرور PGRP")
                    .setMessage("سرور: "+GameNetworkProbe.SERVER+":"+GameNetworkProbe.PORT
                        +"\n\nوضعیت Query:\n"+line+"\n\nدست‌دهی اولیه RakNet:\n"+details
                        +"\n\nاین آزمون به‌معنی ورود بازیکن یا همگام‌سازی واقعی با گیم‌مود نیست.")
                    .setPositiveButton("بستن",null).show();
            });
        });
    }

    @Override protected void onResume(){super.onResume();if(surface!=null)surface.onResume();}
    @Override protected void onPause(){if(surface!=null)surface.onPause();super.onPause();}
    @Override protected void onDestroy(){io.shutdownNow();handler.removeCallbacksAndMessages(null);super.onDestroy();}
}
