from pathlib import Path
import sys

root=Path(sys.argv[1])
activity=root/"PgrpRealModelViewerActivity.java"
glview=root/"PgrpTexturedModelView.java"
s=activity.read_text(encoding="utf-8")
def replace(old,new):
    global s
    if old not in s:
        raise RuntimeError("Cannot patch 0.5.0 activity; marker absent: "+old[:120])
    s=s.replace(old,new,1)

replace("REAL GTA DFF/TXD PREVIEW  ·  v0.5.0","REAL GTA DFF/TXD PREVIEW  ·  v0.5.1")
replace("            final String sharedInfo=sharedDetails;",
        """            final String sharedInfo=sharedDetails;
            final GtaTextureDiagnostics.Result textureDiagnostic=GtaTextureDiagnostics.inspect(loaded);""")
replace("screen.addView(info);screen.addView(display,new LinearLayout.LayoutParams(-1,0,1));",
        """info.setTextSize(12);
                 screen.addView(info);
                 TextView diagnosticText=label(textureDiagnostic.summary);
                 diagnosticText.setTextSize(12);
                 screen.addView(diagnosticText);
                 if(textureDiagnostic.thumbnail!=null){
                    android.widget.ImageView originalTexture=new android.widget.ImageView(this);
                    originalTexture.setImageBitmap(textureDiagnostic.thumbnail);
                    originalTexture.setScaleType(android.widget.ImageView.ScaleType.FIT_CENTER);
                    originalTexture.setBackgroundColor(Color.rgb(26,35,47));
                    screen.addView(originalTexture,new LinearLayout.LayoutParams(-1,68));
                 }
                 screen.addView(display,new LinearLayout.LayoutParams(-1,0,1));""")
replace('Button back=button("Back to asset selection");screen.addView(back);back.setOnClickListener(v->{display.onPause();initUi();});',
        """LinearLayout actions=new LinearLayout(this);
                 actions.setOrientation(LinearLayout.HORIZONTAL);
                 final boolean[] checking={false};
                 Button checker=button("UV TEST: OFF");
                 actions.addView(checker,new LinearLayout.LayoutParams(0,-2,1));
                 checker.setOnClickListener(v->{
                    checking[0]=!checking[0];
                    display.setDebugUV(checking[0]);
                    checker.setText(checking[0]?"UV TEST: ON":"UV TEST: OFF");
                 });
                 Button back=button("Back to asset selection");
                 actions.addView(back,new LinearLayout.LayoutParams(0,-2,1));
                 screen.addView(actions);
                 back.setOnClickListener(v->{display.onPause();initUi();});""")
activity.write_text(s,encoding="utf-8")

r=glview.read_text(encoding="utf-8")
def patch(old,new):
    global r
    if old not in r: raise RuntimeError("Cannot patch OpenGL renderer: "+old[:100])
    r=r.replace(old,new,1)
patch("    @Override public boolean onTouchEvent(MotionEvent e){",
      """    /** Force synthetic diagnostic UV colors instead of reading any GTA texture. */
    public void setDebugUV(boolean enabled){renderer.debugUV=enabled;}
    @Override public boolean onTouchEvent(MotionEvent e){""")
patch("        volatile float yaw=20,pitch=-15;",
      """        volatile float yaw=20,pitch=-15;
        volatile boolean debugUV=false;""")
patch("            for(Map.Entry<String,RenderWareTxd.Texture> item:data.textureByName.entrySet()){",
      """            int[] checker=new int[64*64];
            for(int y=0;y<64;y++)for(int x=0;x<64;x++){
                checker[y*64+x]=((x/8+y/8)&1)==0?0xffff00aa:0xff00dddd;
            }
            gpuTextures.put("__diagnostic_uv_checker__",upload(64,64,checker));
            for(Map.Entry<String,RenderWareTxd.Texture> item:data.textureByName.entrySet()){""")
patch('                int texture=gpuTextures.containsKey(b.texture)?gpuTextures.get(b.texture):gpuTextures.get("");',
      """                int texture=debugUV?gpuTextures.get("__diagnostic_uv_checker__"):
                    (gpuTextures.containsKey(b.texture)?gpuTextures.get(b.texture):gpuTextures.get(""));""")
glview.write_text(r,encoding="utf-8")
print("PASS: v0.5.1 UV debugger and CPU TXD thumbnail integrated")
