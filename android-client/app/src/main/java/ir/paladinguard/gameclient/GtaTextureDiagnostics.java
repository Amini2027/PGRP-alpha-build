package ir.paladinguard.gameclient;
import android.graphics.Bitmap;
import java.util.Locale;
/** CPU-side source TXD and UV inspection; no asset upload or game engine dependency. */
public final class GtaTextureDiagnostics {
  private GtaTextureDiagnostics(){}
  public static final class Result {
    public final String summary; public final Bitmap thumbnail;
    Result(String s,Bitmap b){summary=s;thumbnail=b;}
  }
  public static Result inspect(GtaWorldModelLoader.ModelData d){
    if(d==null||d.geometry.meshes.isEmpty())return new Result("No supported mesh",null);
    GtaDffGeometry.Mesh m=d.geometry.meshes.get(0);
    int id=m.materialIndex.length>0?m.materialIndex[0]:-1;
    String name=(id>=0&&id<d.materials.materialTextureNames.size())?
       d.materials.materialTextureNames.get(id):"";
    RenderWareTxd.Texture t=d.textureByName.get(name);
    float u0=Float.POSITIVE_INFINITY,u1=Float.NEGATIVE_INFINITY,v0=Float.POSITIVE_INFINITY,v1=Float.NEGATIVE_INFINITY;
    for(int i=0;i+1<m.uv.length;i+=2)if(Float.isFinite(m.uv[i])&&Float.isFinite(m.uv[i+1])){
       u0=Math.min(u0,m.uv[i]);u1=Math.max(u1,m.uv[i]);
       v0=Math.min(v0,m.uv[i+1]);v1=Math.max(v1,m.uv[i+1]);}
    String uv=String.format(Locale.US,"UV U: %.3f..%.3f V: %.3f..%.3f",u0,u1,v0,v1);
    if(t==null)return new Result("Active material #"+id+" ("+name+") has no matching texture. "+uv,null);
    String fmt=t.format==RenderWareTxd.DXT1?"DXT1":t.format==RenderWareTxd.DXT3?"DXT3":
      t.format==RenderWareTxd.DXT5?"DXT5":t.format==RenderWareTxd.A8R8G8B8?"ARGB32":
      t.format==RenderWareTxd.X8R8G8B8?"RGB32":"unsupported "+t.format;
    String head="Used material #"+id+" = "+name+" | "+t.width+"x"+t.height+" "+fmt+"\n"+uv;
    if(!t.canDecode())return new Result(head+"\nTexture format not supported by GL preview",null);
    if((long)t.width*t.height>1048576L)return new Result(head+"\nSource texture too large to inspect",null);
    try{
      int[] pixels=t.toArgb(),sample=new int[4096];
      int white=0,black=0,colored=0,transparent=0;
      for(int y=0;y<64;y++)for(int x=0;x<64;x++){
        int c=pixels[Math.min(t.height-1,y*t.height/64)*t.width+Math.min(t.width-1,x*t.width/64)];
        sample[y*64+x]=c;int a=(c>>>24)&255,r=(c>>>16)&255,g=(c>>>8)&255,b=c&255;
        if(r>=235&&g>=235&&b>=235)white++;
        if(r<=24&&g<=24&&b<=24)black++;
        if(Math.max(r,Math.max(g,b))-Math.min(r,Math.min(g,b))>30)colored++;
        if(a<128)transparent++;
      }
      Bitmap bmp=Bitmap.createBitmap(sample,64,64,Bitmap.Config.ARGB_8888);
      return new Result(head+String.format(Locale.US,
          "\nSource image pixels: white %d%% | black %d%% | color %d%% | transparent %d%%",
          white*100/4096,black*100/4096,colored*100/4096,transparent*100/4096),bmp);
    }catch(Exception e){return new Result(head+"\nTXD decode error: "+e.getClass().getSimpleName()+": "+e.getMessage(),null);}
  }
}