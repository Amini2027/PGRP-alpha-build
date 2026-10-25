package ir.paladinguard.roleplay;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.ActivityNotFoundException;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.Intent;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.LinearGradient;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.Shader;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.text.InputFilter;
import android.text.InputType;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.inputmethod.InputMethodManager;
import android.widget.Button;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicBoolean;

/** Independent Android companion launcher. Does not package GTA game content. */
public final class MainActivity extends Activity {
    private static final int BACK = Color.rgb(7, 14, 23);
    private static final int PANEL = Color.rgb(16, 29, 44);
    private static final int PANEL2 = Color.rgb(23, 39, 56);
    private static final int GOLD = Color.rgb(235, 188, 104);
    private static final int WHITE = Color.rgb(239, 245, 248);
    private static final int MUTED = Color.rgb(142, 163, 184);
    private static final int CYAN = Color.rgb(89, 203, 234);
    private static final int GREEN = Color.rgb(105, 215, 159);
    private static final int RED = Color.rgb(239, 105, 103);
    private static final String ADDRESS = ServerQuery.HOST + ":" + ServerQuery.PORT;

    private final Handler ui = new Handler(Looper.getMainLooper());
    private final ExecutorService io = Executors.newSingleThreadExecutor();
    private final AtomicBoolean querying = new AtomicBoolean(false);
    private final Runnable refreshJob = new Runnable() {
        @Override public void run() {
            queryServer();
            ui.postDelayed(this, 30000);
        }
    };
    private TextView statusLabel;
    private TextView playerLabel;
    private TextView pingLabel;
    private TextView serverTitle;
    private TextView indicator;
    private EditText nameField;

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        getWindow().setStatusBarColor(BACK);
        getWindow().setNavigationBarColor(BACK);
        getWindow().getDecorView().setSystemUiVisibility(0);
        buildScreen();
    }

    @Override protected void onResume() {
        super.onResume();
        ui.removeCallbacks(refreshJob);
        ui.post(refreshJob);
    }

    @Override protected void onPause() {
        ui.removeCallbacks(refreshJob);
        saveNick();
        super.onPause();
    }

    @Override protected void onDestroy() {
        ui.removeCallbacks(refreshJob);
        io.shutdownNow();
        super.onDestroy();
    }

    private int dp(float n) { return (int)(getResources().getDisplayMetrics().density * n + 0.5f); }

    private GradientDrawable shape(int fill, int radius, int stroke) {
        GradientDrawable d = new GradientDrawable();
        d.setColor(fill);
        d.setCornerRadius(dp(radius));
        if (stroke != 0) d.setStroke(dp(1), stroke);
        return d;
    }

    private TextView text(String value, int size, int color, boolean bold) {
        TextView t = new TextView(this);
        t.setText(value);
        t.setTextColor(color);
        t.setTextSize(size);
        t.setTypeface(Typeface.create(bold ? "sans-serif-medium" : "sans-serif", bold ? Typeface.BOLD : Typeface.NORMAL));
        t.setGravity(Gravity.CENTER_VERTICAL);
        t.setIncludeFontPadding(false);
        return t;
    }

    private LinearLayout vertical() {
        LinearLayout l = new LinearLayout(this);
        l.setOrientation(LinearLayout.VERTICAL);
        return l;
    }

    private LinearLayout horizontal() {
        LinearLayout l = new LinearLayout(this);
        l.setOrientation(LinearLayout.HORIZONTAL);
        l.setGravity(Gravity.CENTER_VERTICAL);
        return l;
    }

    private LinearLayout.LayoutParams full(int top) {
        LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(-1, -2);
        p.topMargin = dp(top);
        return p;
    }

    private TextView tag(String value, int color) {
        TextView t = text(value, 11, color, true);
        t.setPadding(dp(12),dp(8),dp(12),dp(8));
        t.setBackground(shape(PANEL2, 30, color == CYAN ? 0x4459CBEA : 0x446A7F90));
        return t;
    }

    private void buildScreen() {
        FrameLayout root = new FrameLayout(this);
        root.setBackgroundColor(BACK);
        root.addView(new GridBackdrop(this), new FrameLayout.LayoutParams(-1,-1));

        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        scroll.setClipToPadding(false);
        scroll.setVerticalScrollBarEnabled(false);
        root.addView(scroll, new FrameLayout.LayoutParams(-1,-1));
        setContentView(root);

        LinearLayout body = vertical();
        body.setPadding(dp(22),dp(26),dp(22),dp(36));
        scroll.addView(body);

        // Brand header
        LinearLayout header = horizontal();
        TextView shield = text("PG", 20, GOLD, true);
        shield.setGravity(Gravity.CENTER);
        shield.setBackground(shape(PANEL, 17, GOLD));
        header.addView(shield, new LinearLayout.LayoutParams(dp(56),dp(56)));
        LinearLayout brand = vertical();
        brand.setPadding(dp(13),0,0,0);
        TextView brandName = text("PALADIN GUARD", 18, WHITE, true);
        brandName.setLetterSpacing(0.105f);
        brand.addView(brandName);
        TextView brandSub = text("ROLEPLAY  /  ANDROID", 11, GOLD, true);
        brandSub.setLetterSpacing(0.10f);
        LinearLayout.LayoutParams subP=full(4);
        brand.addView(brandSub,subP);
        header.addView(brand,new LinearLayout.LayoutParams(0,-2,1));
        TextView ver = tag("ALPHA 0.1", MUTED);
        header.addView(ver);
        body.addView(header);

        // Hero
        FrameLayout heroFrame = new FrameLayout(this);
        GradientDrawable heroBg = new GradientDrawable(GradientDrawable.Orientation.TL_BR,
            new int[]{0xFF14283C,0xFF101C2C,0xFF1C222D});
        heroBg.setCornerRadius(dp(24));
        heroBg.setStroke(dp(1),0x6659CBEA);
        heroFrame.setBackground(heroBg);
        LinearLayout hero = vertical();
        hero.setPadding(dp(20),dp(23),dp(20),dp(22));
        heroFrame.addView(hero,new FrameLayout.LayoutParams(-1,-2));
        TextView small = text("THE WORLD IS YOURS", 10, CYAN, true);
        small.setLetterSpacing(.16f);
        hero.addView(small);

        TextView heroTitle = text("PALADIN\nGUARD", 36, WHITE, true);
        heroTitle.setLineSpacing(dp(-3),1f);
        heroTitle.setLetterSpacing(.055f);
        hero.addView(heroTitle,full(11));

        TextView heroSub = text("ROLEPLAY • IRAN SERVER", 12, GOLD, true);
        heroSub.setLetterSpacing(.08f);
        hero.addView(heroSub,full(8));

        View rule = new View(this);
        rule.setBackgroundColor(0x3359CBEA);
        LinearLayout.LayoutParams line=full(22);
        line.height=dp(1);
        hero.addView(rule,line);

        LinearLayout stateRow = horizontal();
        indicator = text("●",14,CYAN,true);
        stateRow.addView(indicator);
        statusLabel = text("در حال بررسی وضعیت سرور...",13,WHITE,false);
        statusLabel.setPadding(dp(9),0,0,0);
        stateRow.addView(statusLabel,new LinearLayout.LayoutParams(0,-2,1));
        TextView refresh = tag("↻", CYAN);
        refresh.setContentDescription("بروزرسانی وضعیت");
        refresh.setOnClickListener(v -> queryServer());
        stateRow.addView(refresh);
        hero.addView(stateRow,full(18));
        body.addView(heroFrame, full(28));

        // Stats
        LinearLayout stats = horizontal();
        stats.setGravity(Gravity.TOP);
        LinearLayout s1=statBlock("PLAYERS","—", "بازیکنان", CYAN);
        LinearLayout s2=statBlock("PING","—", "میلی‌ثانیه", GOLD);
        LinearLayout s3=statBlock("REGION","IR", "ایران", GREEN);
        playerLabel=(TextView)s1.getChildAt(1);
        pingLabel=(TextView)s2.getChildAt(1);
        LinearLayout.LayoutParams statWidth=new LinearLayout.LayoutParams(0,dp(107),1);
        statWidth.rightMargin=dp(8);stats.addView(s1,statWidth);
        LinearLayout.LayoutParams middle=new LinearLayout.LayoutParams(0,dp(107),1);
        middle.rightMargin=dp(8);stats.addView(s2,middle);
        stats.addView(s3,new LinearLayout.LayoutParams(0,dp(107),1));
        body.addView(stats,full(12));

        section(body,"ورود به بازی","CONNECT TO SERVER",26);
        LinearLayout ipCard = horizontal();
        ipCard.setPadding(dp(16),dp(15),dp(12),dp(15));
        ipCard.setBackground(shape(PANEL,17,0x334E7790));
        LinearLayout ipLeft=vertical();
        ipLeft.addView(text("SERVER ADDRESS",10,MUTED,true));
        TextView ip=text(ADDRESS,17,WHITE,true);
        ip.setLetterSpacing(.03f);
        ipLeft.addView(ip,full(6));
        ipCard.addView(ipLeft,new LinearLayout.LayoutParams(0,-2,1));
        TextView copy=tag("کپی",GOLD);
        copy.setOnClickListener(v->copyIp());
        ipCard.addView(copy);
        body.addView(ipCard,full(11));

        nameField=new EditText(this);
        nameField.setSingleLine(true);
        nameField.setTextColor(WHITE);
        nameField.setHintTextColor(MUTED);
        nameField.setTextSize(15);
        nameField.setPadding(dp(16),dp(13),dp(16),dp(13));
        nameField.setHint("نام بازیکن  •  First_Last");
        nameField.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS);
        nameField.setFilters(new InputFilter[]{new InputFilter.LengthFilter(24)});
        nameField.setText(getPreferences(MODE_PRIVATE).getString("nickname",""));
        nameField.setBackground(shape(PANEL,15,0x3359CBEA));
        nameField.setTextDirection(View.TEXT_DIRECTION_LTR);
        body.addView(nameField,full(12));

        Button play=button("ورود به بازی  ←",GOLD,BACK);
        play.setOnClickListener(v->play());
        body.addView(play,full(14));
        TextView note=text("برای ورود، یک کلاینت سازگار SA-MP اندروید لازم است. این برنامه فایل‌های GTA را شامل نمی‌شود.",12,MUTED,false);
        note.setGravity(Gravity.RIGHT);
        note.setTextDirection(View.TEXT_DIRECTION_RTL);
        note.setLineSpacing(dp(4),1f);
        body.addView(note,full(12));

        section(body,"ابزارها و راهنما","TOOLS & SUPPORT",27);
        LinearLayout toolRow=horizontal();
        Button guide=button("راهنمای نصب",PANEL,WHITE);
        guide.setOnClickListener(v->showGuide());
        LinearLayout.LayoutParams half=new LinearLayout.LayoutParams(0,dp(53),1);
        half.rightMargin=dp(9);toolRow.addView(guide,half);
        Button site=button("وب‌سایت",PANEL,WHITE);
        site.setOnClickListener(v->openUrl("https://paladinguard.ir"));
        toolRow.addView(site,new LinearLayout.LayoutParams(0,dp(53),1));
        body.addView(toolRow,full(12));

        LinearLayout news=vertical();
        news.setPadding(dp(17),dp(16),dp(17),dp(17));
        news.setBackground(shape(PANEL,17,0x3359CBEA));
        TextView title=text("اطلاعیه نسخه آزمایشی",15,GOLD,true);
        title.setGravity(Gravity.RIGHT);
        news.addView(title);
        TextView desc=text("لانچر اندروید PGRP آماده تست اولیه است. اتصال مستقیم به محیط بازی به سازگاری کلاینت موبایل با سرور بستگی دارد.",13,WHITE,false);
        desc.setGravity(Gravity.RIGHT);
        desc.setLineSpacing(dp(4),1f);
        news.addView(desc,full(10));
        body.addView(news,full(17));

        TextView footer=text("PGRP  •  MOBILE LAUNCHER 0.1.0\nMade for the Paladin Guard community",10,MUTED,false);
        footer.setGravity(Gravity.CENTER);
        footer.setLineSpacing(dp(4),1f);
        body.addView(footer,full(28));
    }

    private LinearLayout statBlock(String label,String value,String subtitle,int accent){
        LinearLayout card=vertical();
        card.setPadding(dp(13),dp(13),dp(10),dp(10));
        card.setBackground(shape(PANEL,15,0x334E7790));
        TextView top=text(label,10,MUTED,true);top.setLetterSpacing(.08f);card.addView(top);
        card.addView(text(value,21,accent,true),full(8));
        card.addView(text(subtitle,10,MUTED,false),full(6));
        return card;
    }

    private Button button(String title,int background,int foreground){
        Button b=new Button(this);
        b.setAllCaps(false);
        b.setText(title);
        b.setTextSize(15);
        b.setTypeface(Typeface.create("sans-serif-medium",Typeface.BOLD));
        b.setTextColor(foreground);
        b.setBackground(shape(background,14,background==PANEL?0x3359CBEA:0));
        b.setElevation(dp(2));
        b.setPadding(dp(12),0,dp(12),0);
        b.setMinimumHeight(dp(52));
        return b;
    }

    private void section(LinearLayout parent,String fa,String en,int gap){
        LinearLayout box=vertical();
        TextView label=text(fa,20,WHITE,true);
        label.setGravity(Gravity.RIGHT);
        box.addView(label);
        TextView subtitle=text(en,10,GOLD,true);
        subtitle.setLetterSpacing(.14f);
        subtitle.setGravity(Gravity.RIGHT);
        box.addView(subtitle,full(6));
        parent.addView(box,full(gap));
    }

    private void saveNick(){
        if(nameField==null)return;
        getPreferences(MODE_PRIVATE).edit().putString("nickname",
            nameField.getText().toString().trim()).apply();
    }

    private void copyIp(){
        ClipboardManager clipboard=(ClipboardManager)getSystemService(Context.CLIPBOARD_SERVICE);
        clipboard.setPrimaryClip(ClipData.newPlainText("PGRP server",ADDRESS));
        Toast.makeText(this,"آدرس سرور کپی شد",Toast.LENGTH_SHORT).show();
    }

    private void play(){
        String nick=nameField.getText().toString().trim();
        if(!nick.matches("[A-Za-z0-9_]{3,24}")){
            nameField.setError("نام لاتین ۳ تا ۲۴ کاراکتر، بدون فاصله");
            nameField.requestFocus();
            return;
        }
        saveNick();
        try{
            Intent deepLink = new Intent(Intent.ACTION_VIEW,Uri.parse("samp://"+ADDRESS));
            deepLink.addCategory(Intent.CATEGORY_BROWSABLE);
            startActivity(deepLink);
        }catch(ActivityNotFoundException e){
            copyIp();
            new AlertDialog.Builder(this)
                .setTitle("کلاینت بازی پیدا نشد")
                .setMessage("آدرس سرور کپی شد. داخل کلاینت معتبر SA-MP اندروید، سرور "
                    + ADDRESS + " را در Favorites / Add Server ثبت کن. این لانچر بازی GTA را نصب یا اجرا نمی‌کند.")
                .setPositiveButton("متوجه شدم",(d,w)->{})
                .setNeutralButton("راهنما",(d,w)->showGuide())
                .show();
        }catch(Exception e){
            copyIp();
            Toast.makeText(this,"ورود مستقیم پشتیبانی نشد؛ آدرس سرور کپی شد",Toast.LENGTH_LONG).show();
        }
    }

    private void showGuide(){
        new AlertDialog.Builder(this)
            .setTitle("راه‌اندازی PGRP اندروید")
            .setMessage("۱) یک نسخه قانونی GTA San Andreas برای اندروید تهیه کن.\n\n"
                +"۲) یک کلاینت SA-MP اندروید سازگار را از منبع معتبر نصب کن؛ این برنامه مستقل از کلاینت بازی است.\n\n"
                +"۳) در کلاینت موبایل، سرور "+ADDRESS+" را به فهرست اضافه کن.\n\n"
                +"۴) نام بازیکن را مطابق قوانین سرور وارد کن.\n\n"
                +"۵) ورود و عملکرد داخل بازی به سازگاری کلاینت موبایل و تنظیمات سرور بستگی دارد.")
            .setPositiveButton("کپی آدرس",(d,w)->copyIp())
            .setNeutralButton("جستجو در فروشگاه",(d,w)->openUrl("https://play.google.com/store/search?q=SA-MP%20Android&c=apps"))
            .setNegativeButton("بستن",null)
            .show();
    }

    private void openUrl(String url){
        try{
            startActivity(new Intent(Intent.ACTION_VIEW,Uri.parse(url)));
        }catch(Exception e){
            Toast.makeText(this,"برنامه مرورگر در دسترس نیست",Toast.LENGTH_SHORT).show();
        }
    }

    private void queryServer(){
        if(!querying.compareAndSet(false,true))return;
        if(statusLabel!=null){statusLabel.setText("در حال بررسی وضعیت سرور...");indicator.setTextColor(CYAN);}
        io.submit(()->{
            ServerQuery.Status response=null;
            try{response=ServerQuery.read();}catch(Exception ignored){/* no query reply != offline */}
            final ServerQuery.Status status=response;
            querying.set(false);
            ui.post(()->{
                if(isFinishing() || isDestroyed() || statusLabel==null)return;
                if(status==null){
                    indicator.setTextColor(GOLD);
                    statusLabel.setText("پاسخ وضعیت دریافت نشد");
                    playerLabel.setText("—");
                    pingLabel.setText("—");
                }else{
                    indicator.setTextColor(GREEN);
                    statusLabel.setText("سرور پاسخ می‌دهد  •  ONLINE");
                    playerLabel.setText(status.players+"/"+status.maxPlayers);
                    pingLabel.setText(status.pingMs+"ms");
                }
            });
        });
    }

    // Deterministic, allocation-light patterned backdrop; no game assets.
    private static final class GridBackdrop extends View {
        private final Paint paint=new Paint(Paint.ANTI_ALIAS_FLAG);
        GridBackdrop(Context context){super(context);}
        @Override protected void onDraw(Canvas c){
            super.onDraw(c);
            int w=getWidth(),h=getHeight();
            c.drawColor(BACK);
            paint.setShader(new LinearGradient(0,0,w,h,
                new int[]{0xFF091827,0xFF070E17,0xFF191019},null,Shader.TileMode.CLAMP));
            c.drawRect(0,0,w,h,paint);
            paint.setShader(null);
            float density=getResources().getDisplayMetrics().density;
            float step=32*density;
            paint.setStrokeWidth(density*.55f);
            paint.setColor(0x102BB5DE);
            for(float x=0;x<w;x+=step)c.drawLine(x,0,x,h,paint);
            for(float y=0;y<h;y+=step)c.drawLine(0,y,w,y,paint);
            paint.setStyle(Paint.Style.STROKE);
            paint.setStrokeWidth(density);
            paint.setColor(0x166FC7E5);
            for(int i=0;i<4;i++){
                float radius=(65+i*45)*density;
                c.drawCircle(w*.88f,h*.24f,radius,paint);
            }
            paint.setStyle(Paint.Style.FILL);
        }
    }
}
