from pathlib import Path
import sys

root=Path(sys.argv[1])
activity=root/"PgrpRealModelViewerActivity.java"
glview=root/"PgrpTexturedModelView.java"
s=activity.read_text(encoding="utf-8")
def replace(old,new):
    global s
    if old not in s:
        raise RuntimeError("v052 activity patch marker missing: "+old[:110])
    s=s.replace(old,new,1)

replace("REAL GTA DFF/TXD PREVIEW  ·  v0.5.1","REAL GTA DFF/TXD PREVIEW  ·  v0.5.2")
replace("root.addView(modelText);","""root.addView(modelText);
        Button browse=button("Browse other DFF models in gta3.img");root.addView(browse);
        browse.setOnClickListener(v->browseModels());""")

replace("    private void preview(){", """    /** Read a small list of model names without extracting GTA assets. */
    private void browseModels(){
      if(imgUri==null){report("Select your gta3.img archive first");return;}
      final EditText search=new EditText(this);
      search.setSingleLine(true);
      search.setTextColor(Color.BLACK);
      search.setHint("Search model name: house, shop, tower, car...");
      new android.app.AlertDialog.Builder(this).setTitle("Find DFF in GTA IMG")
        .setMessage("Use part of a model name; choose a result to fill DFF and auto TXD.")
        .setView(search).setNegativeButton("Cancel",null)
        .setPositiveButton("Search",(dialog,which)->{
          final String query=search.getText().toString().trim().toLowerCase(Locale.ROOT);
          if(query.length()>40){report("Search text too long");return;}
          task(()->{
            try(ParcelFileDescriptor descriptor=getContentResolver().openFileDescriptor(imgUri,"r")){
              if(descriptor==null)throw new IOException("Cannot open selected IMG");
              try(GtaImgV2 archive=new GtaImgV2(new FileInputStream(descriptor.getFileDescriptor()))){
                java.util.ArrayList<String> matches=new java.util.ArrayList<>();
                for(String name:archive.directory().keySet()){
                  if(!name.endsWith(".dff"))continue;
                  if(!query.isEmpty()&&!name.contains(query))continue;
                  if(query.isEmpty() && !(name.contains("house")||name.contains("shop")
                    ||name.contains("tower")||name.contains("hotel")||name.contains("tree")
                    ||name.contains("palm")||name.contains("garage")||name.contains("bld")
                    ||name.contains("sign")||name.contains("building")))continue;
                  matches.add(name.substring(0,name.length()-4));
                  if(matches.size()>=60)break;
                }
                final String[] names=matches.toArray(new String[0]);
                runOnUiThread(()->{
                  if(isFinishing()||isDestroyed())return;
                  if(names.length==0){
                    report("No matching DFF models; try another search such as 'car', 'shop', 'house'");
                    return;
                  }
                  new android.app.AlertDialog.Builder(this).setTitle("Select DFF ("+names.length+" results)")
                    .setItems(names,(dlg,index)->{
                      modelText.setText(names[index]);
                      txdText.setText("auto");
                      report("Selected "+names[index]+". TXD=auto. Tap Preview. Some GTA models may use unsupported native geometries.");
                    }).setNegativeButton("Cancel",null).show();
                });
              }
            }catch(Exception e){report("DFF model search failed: "+e.getMessage());}
          });
        }).show();
    }
    private void preview(){""")

replace("screen.addView(originalTexture,new LinearLayout.LayoutParams(-1,68));",
        """screen.addView(originalTexture,new LinearLayout.LayoutParams(-1,
                      (int)(92*getResources().getDisplayMetrics().density)));
                    originalTexture.setOnClickListener(v->{
                      android.widget.ImageView big=new android.widget.ImageView(this);
                      big.setImageBitmap(textureDiagnostic.thumbnail);
                      big.setScaleType(android.widget.ImageView.ScaleType.FIT_CENTER);
                      big.setBackgroundColor(Color.rgb(24,28,33));
                      big.setMinimumHeight((int)(260*getResources().getDisplayMetrics().density));
                      new android.app.AlertDialog.Builder(this)
                        .setTitle("Actual TXD texture - tap outside to close")
                        .setView(big).setPositiveButton("Close",null).show();
                    });""")

replace('Button back=button("Back to asset selection");',
        """final boolean[] lit={false};
                 Button shading=button("SHADING: UNLIT");
                 actions.addView(shading,new LinearLayout.LayoutParams(0,-2,1));
                 shading.setOnClickListener(v->{
                   lit[0]=!lit[0];
                   display.setLit(lit[0]);
                   shading.setText(lit[0]?"SHADING: LIT":"SHADING: UNLIT");
                 });
                 Button browseAgain=button("Another DFF");
                 actions.addView(browseAgain,new LinearLayout.LayoutParams(0,-2,1));
                 browseAgain.setOnClickListener(v->{display.onPause();initUi();browseModels();});
                 Button back=button("Back");""")
activity.write_text(s,encoding="utf-8")

r=glview.read_text(encoding="utf-8")
def patch(old,new):
    global r
    if old not in r:raise RuntimeError("v052 OpenGL patch marker missing: "+old[:115])
    r=r.replace(old,new,1)

patch('public void setDebugUV(boolean enabled){renderer.debugUV=enabled;}',
      '''public void setDebugUV(boolean enabled){renderer.debugUV=enabled;}
    /** Original v0.5.1 shader is already unlit. This enables optional simulated diffuse lighting. */
    public void setLit(boolean enabled){renderer.litMode=enabled;}''')

patch('volatile boolean debugUV=false;',
      'volatile boolean debugUV=false,litMode=false;')

patch('private int program,aPos,aUv,uMvp,uTex;',
      'private int program,aPos,aUv,aNormal,uMvp,uModel,uLit,uTex;')

patch('''                for(int j=0;j<3;j++){
                    int k=m.indices[3*t+j];''',
      '''                int ia=m.indices[3*t],ib=m.indices[3*t+1],ic=m.indices[3*t+2];
                float ax=m.xyz[ia*3],ay=m.xyz[ia*3+1],az=m.xyz[ia*3+2];
                float bx=m.xyz[ib*3],by=m.xyz[ib*3+1],bz=m.xyz[ib*3+2];
                float cxn=m.xyz[ic*3],cyn=m.xyz[ic*3+1],czn=m.xyz[ic*3+2];
                float ex=bx-ax,ey=by-ay,ez=bz-az,fx=cxn-ax,fy=cyn-ay,fz=czn-az;
                float nx=ey*fz-ez*fy,ny=ez*fx-ex*fz,nz=ex*fy-ey*fx;
                float len=(float)Math.sqrt(nx*nx+ny*ny+nz*nz);
                if(len<1.0e-8f){nx=0;ny=0;nz=1;} else{nx/=len;ny/=len;nz/=len;}
                for(int j=0;j<3;j++){
                    int k=m.indices[3*t+j];''')
patch('''dest.add(m.uv[k*2]);dest.add(1f-m.uv[k*2+1]);''',
      '''dest.add(m.uv[k*2]);dest.add(1f-m.uv[k*2+1]);
                    dest.add(nx);dest.add(ny);dest.add(nz);''')
patch('batches.add(new Batch(tex,floats(a),a.length/5));',
      'batches.add(new Batch(tex,floats(a),a.length/8));')

patch('''int vs=compile(GLES20.GL_VERTEX_SHADER,"attribute vec3 aPos; attribute vec2 aUV; uniform mat4 uMVP; varying vec2 vUV; void main(){vUV=aUV; gl_Position=uMVP*vec4(aPos,1.0);}");''',
      '''int vs=compile(GLES20.GL_VERTEX_SHADER,
                "attribute vec3 aPos; attribute vec2 aUV; attribute vec3 aNormal; "+
                "uniform mat4 uMVP; uniform mat4 uModel; varying vec2 vUV; varying float vShade; "+
                "void main(){vUV=aUV;vec3 n=normalize((uModel*vec4(aNormal,0.0)).xyz);"+
                "vShade=0.26+0.74*max(dot(n,normalize(vec3(0.3,0.8,0.55))),0.0);"+
                "gl_Position=uMVP*vec4(aPos,1.0);}");''')
patch('''int fs=compile(GLES20.GL_FRAGMENT_SHADER,"precision mediump float; varying vec2 vUV; uniform sampler2D uTexture; void main(){gl_FragColor=texture2D(uTexture,vUV);}");''',
      '''int fs=compile(GLES20.GL_FRAGMENT_SHADER,
                "precision mediump float; varying vec2 vUV; varying float vShade;"+
                "uniform sampler2D uTexture; uniform float uLit;"+
                "void main(){vec4 c=texture2D(uTexture,vUV);"+
                "gl_FragColor=vec4(c.rgb*mix(1.0,vShade,uLit),c.a);}");''')
patch('''aPos=GLES20.glGetAttribLocation(program,"aPos");aUv=GLES20.glGetAttribLocation(program,"aUV");''',
      '''aPos=GLES20.glGetAttribLocation(program,"aPos");aUv=GLES20.glGetAttribLocation(program,"aUV");
            aNormal=GLES20.glGetAttribLocation(program,"aNormal");''')
patch('''uMvp=GLES20.glGetUniformLocation(program,"uMVP");uTex=GLES20.glGetUniformLocation(program,"uTexture");''',
      '''uMvp=GLES20.glGetUniformLocation(program,"uMVP");uTex=GLES20.glGetUniformLocation(program,"uTexture");
            uModel=GLES20.glGetUniformLocation(program,"uModel");
            uLit=GLES20.glGetUniformLocation(program,"uLit");''')
patch('''GLES20.glUseProgram(program);GLES20.glUniformMatrix4fv(uMvp,1,false,mvp,0);''',
      '''GLES20.glUseProgram(program);GLES20.glUniformMatrix4fv(uMvp,1,false,mvp,0);
            GLES20.glUniformMatrix4fv(uModel,1,false,model,0);
            GLES20.glUniform1f(uLit,litMode?1f:0f);''')
patch('''GLES20.glEnableVertexAttribArray(aPos);GLES20.glEnableVertexAttribArray(aUv);''',
      '''GLES20.glEnableVertexAttribArray(aPos);GLES20.glEnableVertexAttribArray(aUv);
            GLES20.glEnableVertexAttribArray(aNormal);''')
patch('''b.verts.position(0);GLES20.glVertexAttribPointer(aPos,3,GLES20.GL_FLOAT,false,20,b.verts);
                b.verts.position(3);GLES20.glVertexAttribPointer(aUv,2,GLES20.GL_FLOAT,false,20,b.verts);''',
      '''b.verts.position(0);GLES20.glVertexAttribPointer(aPos,3,GLES20.GL_FLOAT,false,32,b.verts);
                b.verts.position(3);GLES20.glVertexAttribPointer(aUv,2,GLES20.GL_FLOAT,false,32,b.verts);
                b.verts.position(5);GLES20.glVertexAttribPointer(aNormal,3,GLES20.GL_FLOAT,false,32,b.verts);''')
patch('''GLES20.glDisableVertexAttribArray(aPos);GLES20.glDisableVertexAttribArray(aUv);''',
      '''GLES20.glDisableVertexAttribArray(aPos);GLES20.glDisableVertexAttribArray(aUv);
            GLES20.glDisableVertexAttribArray(aNormal);''')
glview.write_text(r,encoding="utf-8")
assert 'SHADING: UNLIT' in s and 'vShade' in r and 'Another DFF' in s
print("PASS: PGRP v0.5.2 model browser / TXD zoom / unlit-lit shader")
