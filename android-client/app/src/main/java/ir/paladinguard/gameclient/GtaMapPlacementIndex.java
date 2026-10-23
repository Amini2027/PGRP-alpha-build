package ir.paladinguard.gameclient;

import java.io.*;
import java.util.*;

/**
 * Reads GTA San Andreas PC's textual GTA.DAT -> IDE / IPL definitions and
 * placement records, without loading proprietary meshes or copying assets.
 * Binary IPL files inside IMG and DFF/TXD rendering are not implemented.
 */
public final class GtaMapPlacementIndex {
    private GtaMapPlacementIndex() {}
    public static final float CENTER_X=1450f,CENTER_Y=-1700f,PREVIEW_RADIUS=1300f;
    private static final int MAX_PATHS=1400,MAX_LINES=350000,MAX_PREVIEW=12000,MAX_ERRORS=12;
    public interface Source { Reader open(String relativePath) throws IOException; }
    public static final class Instance {
        public final int modelId,interior,lod;
        public final String modelName;
        public final float x,y,z,qx,qy,qz,qw;
        Instance(int id,int interior,int lod,String name,float x,float y,float z,
                 float qx,float qy,float qz,float qw) {
            this.modelId=id;this.interior=interior;this.lod=lod;
            this.modelName=name;this.x=x;this.y=y;this.z=z;
            this.qx=qx;this.qy=qy;this.qz=qz;this.qw=qw;
        }
    }
    public static final class Result {
        public final int idePaths,iplPaths,ideLoaded,iplLoaded,definitions;
        public final int instances,nearbyOutside,missingFiles,invalidRecords;
        public final List<Instance> visibleSamples;
        public final List<String> sampleErrors;
        Result(int idePaths,int iplPaths,int ideLoaded,int iplLoaded,
               int definitions,int instances,int nearbyOutside,int missingFiles,
               int invalidRecords,List<Instance> samples,List<String> errors){
            this.idePaths=idePaths;this.iplPaths=iplPaths;
            this.ideLoaded=ideLoaded;this.iplLoaded=iplLoaded;
            this.definitions=definitions;this.instances=instances;
            this.nearbyOutside=nearbyOutside;this.missingFiles=missingFiles;
            this.invalidRecords=invalidRecords;
            this.visibleSamples=Collections.unmodifiableList(new ArrayList<>(samples));
            this.sampleErrors=Collections.unmodifiableList(new ArrayList<>(errors));
        }
    }
    private static final class State {
        int ide,ipl,instances,nearby,missing,invalid;
        final Map<Integer,String> models=new HashMap<>();
        final List<Instance> samples=new ArrayList<>();
        final List<String> errors=new ArrayList<>();
        void error(String msg){if(errors.size()<MAX_ERRORS)errors.add(msg);}
    }
    public static String normalizeGamePath(String path) throws IOException {
        if(path==null)throw new IOException("Missing GTA path");
        String cleaned=path.trim().replace('\\','/');
        if(cleaned.startsWith("./"))cleaned=cleaned.substring(2);
        String[] components=cleaned.split("/",-1);
        if(components.length<2||components.length>12)throw new IOException("Invalid path");
        StringBuilder result=new StringBuilder();
        for(String segment:components){
            if(segment.isEmpty()||segment.equals(".")||segment.equals("..")||
               segment.indexOf(':')>=0||segment.length()>80)
               throw new IOException("Unsafe relative path");
            if(result.length()>0)result.append('/');
            result.append(segment.toLowerCase(Locale.ROOT));
        }
        String name=result.toString();
        if(!name.startsWith("data/")||
           !(name.endsWith(".ipl")||name.endsWith(".ide")))
            throw new IOException("Only GTA data IPL/IDE can be read");
        return name;
    }
    private static List<String>[] manifest(Reader input) throws IOException {
        Set<String> ide=new LinkedHashSet<>(),ipl=new LinkedHashSet<>();
        try(BufferedReader reader=new BufferedReader(input)){
            String raw;int lines=0;
            while((raw=reader.readLine())!=null){
                if(++lines>MAX_LINES)throw new IOException("Oversized GTA manifest");
                String line=strip(raw);
                int ws=-1;for(int i=0;i<line.length();i++)
                    if(Character.isWhitespace(line.charAt(i))){ws=i;break;}
                if(ws<0)continue;
                String type=line.substring(0,ws).toUpperCase(Locale.ROOT);
                if(!type.equals("IDE")&&!type.equals("IPL"))continue;
                String name=normalizeGamePath(line.substring(ws).trim());
                (type.equals("IDE")?ide:ipl).add(name);
                if(ide.size()+ipl.size()>MAX_PATHS)
                    throw new IOException("Excessive GTA manifest references");
            }
        }
        @SuppressWarnings("unchecked")
        List<String>[] lists=(List<String>[])new List<?>[]{new ArrayList<>(ide),new ArrayList<>(ipl)};
        return lists;
    }
    private static String strip(String raw){
        String s=raw.trim();
        if(s.startsWith("#")||s.startsWith(";")||s.startsWith("//"))return "";
        int comment=s.indexOf('#');
        return comment>=0?s.substring(0,comment).trim():s;
    }
    public static Result read(Reader manifestFile,Source fileSource) throws IOException {
        if(manifestFile==null||fileSource==null)throw new IllegalArgumentException("Missing GTA data source");
        List<String>[] paths=manifest(manifestFile);
        State state=new State();
        for(String path:paths[0]){
            try(Reader input=fileSource.open(path)){
                if(input==null)throw new IOException("File not found");
                readIde(input,state);state.ide++;
            }catch(IOException e){state.missing++;state.error(path+": "+e.getMessage());}
        }
        for(String path:paths[1]){
            try(Reader input=fileSource.open(path)){
                if(input==null)throw new IOException("File not found");
                readIpl(input,state);state.ipl++;
            }catch(IOException e){state.missing++;state.error(path+": "+e.getMessage());}
        }
        return new Result(paths[0].size(),paths[1].size(),state.ide,state.ipl,
            state.models.size(),state.instances,state.nearby,state.missing,state.invalid,
            state.samples,state.errors);
    }
    private static void readIde(Reader input,State state) throws IOException {
        BufferedReader reader=new BufferedReader(input);
        String section="",raw;int lines=0;long chars=0;
        while((raw=reader.readLine())!=null){
            chars+=raw.length();if(++lines>MAX_LINES||chars>12000000L)throw new IOException("IDE too large");
            String s=strip(raw);if(s.isEmpty())continue;
            String lower=s.toLowerCase(Locale.ROOT);
            if(lower.equals("end")){section="";continue;}
            if(s.indexOf(',')<0){section=lower;continue;}
            if(!section.equals("objs")&&!section.equals("tobj")&&!section.equals("anim"))continue;
            String[] parts=s.split(",",-1);
            if(parts.length<3){state.invalid++;continue;}
            try{
                int id=Integer.parseInt(parts[0].trim());String name=parts[1].trim();
                if(id<1||id>65535||name.isEmpty()||name.length()>64){state.invalid++;continue;}
                if(state.models.size()<30000||state.models.containsKey(id))state.models.put(id,name);
            }catch(NumberFormatException ex){state.invalid++;}
        }
    }
    private static void readIpl(Reader input,State state) throws IOException {
        BufferedReader reader=new BufferedReader(input);
        String section="",raw;int lines=0;long chars=0;
        while((raw=reader.readLine())!=null){
            chars+=raw.length();if(++lines>MAX_LINES||chars>12000000L)throw new IOException("IPL too large");
            String s=strip(raw);if(s.isEmpty())continue;
            String lower=s.toLowerCase(Locale.ROOT);
            if(lower.equals("end")){section="";continue;}
            if(s.indexOf(',')<0){section=lower;continue;}
            if(!section.equals("inst"))continue;
            String[] fields=s.split(",",-1);
            if(fields.length!=11){state.invalid++;continue;}
            try{
                int id=Integer.parseInt(fields[0].trim());
                int interior=Integer.parseInt(fields[2].trim());
                float x=Float.parseFloat(fields[3].trim()),y=Float.parseFloat(fields[4].trim()),
                      z=Float.parseFloat(fields[5].trim());
                float qx=Float.parseFloat(fields[6].trim()),qy=Float.parseFloat(fields[7].trim()),
                      qz=Float.parseFloat(fields[8].trim()),qw=Float.parseFloat(fields[9].trim());
                int lod=Integer.parseInt(fields[10].trim());
                if(id<1||id>65535||interior<0||interior>255||
                   !Float.isFinite(x)||!Float.isFinite(y)||!Float.isFinite(z)||
                   !Float.isFinite(qx)||!Float.isFinite(qy)||!Float.isFinite(qz)||!Float.isFinite(qw)||
                   Math.abs(x)>20000||Math.abs(y)>20000||Math.abs(z)>20000) {
                    state.invalid++;continue;
                }
                state.instances++;
                if(interior==0&&Math.abs(x-CENTER_X)<PREVIEW_RADIUS&&
                   Math.abs(y-CENTER_Y)<PREVIEW_RADIUS){
                    state.nearby++;
                    if(state.samples.size()<MAX_PREVIEW)
                        state.samples.add(new Instance(id,interior,lod,
                            state.models.containsKey(id)?state.models.get(id):fields[1].trim(),
                            x,y,z,qx,qy,qz,qw));
                }
            }catch(NumberFormatException ex){state.invalid++;}
        }
    }
}