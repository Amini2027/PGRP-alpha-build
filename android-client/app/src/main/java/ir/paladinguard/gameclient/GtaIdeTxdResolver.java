package ir.paladinguard.gameclient;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.Reader;
import java.util.LinkedHashSet;
import java.util.Locale;
import java.util.Set;

/**
 * Looks up the authoritative DFF -> TXD dictionary mapping using the user's
 * own GTA SA data/gta.dat + referenced data/*.ide files.
 * No heuristic matching by basename and no game data bundled in the APK.
 */
public final class GtaIdeTxdResolver {
    private GtaIdeTxdResolver() {}
    public static final class Result {
        public final String txd;
        public final String source;
        public final int ideFilesChecked;
        public final int idePaths;
        Result(String txd,String source,int checked,int paths) {
            this.txd=txd;this.source=source;this.ideFilesChecked=checked;this.idePaths=paths;
        }
    }
    private static String clean(String line) {
        String s=line.trim();
        if(s.startsWith("#") || s.startsWith(";") || s.startsWith("//"))return "";
        int comment=s.indexOf('#');
        if(comment>=0)s=s.substring(0,comment).trim();
        return s;
    }
    private static boolean allowedSection(String s) {
        return s.equals("objs") || s.equals("tobj") || s.equals("anim") ||
            s.equals("cars") || s.equals("peds") || s.equals("weap") ||
            s.equals("hier");
    }
    public static Result resolve(GtaMapSafSource source,String model)throws IOException {
        if(source==null||model==null)throw new IOException("Missing model or source");
        String wanted=model.trim().toLowerCase(Locale.ROOT);
        if(!wanted.matches("[a-z0-9_.$-]{1,64}"))throw new IOException("Unsafe model name");
        Set<String> paths=new LinkedHashSet<>();
        try(BufferedReader manifest=new BufferedReader(source.openManifest())) {
            String line;int lines=0;
            while((line=manifest.readLine())!=null) {
                if(++lines>15000)throw new IOException("GTA manifest too large");
                String s=clean(line).replace('\\','/');
                int space=0;while(space<s.length()&&!Character.isWhitespace(s.charAt(space)))space++;
                if(space==s.length()||!s.substring(0,space).equalsIgnoreCase("IDE"))continue;
                String path=s.substring(space).trim();
                if(!path.toLowerCase(Locale.ROOT).endsWith(".ide"))continue;
                try {
                    paths.add(GtaMapPlacementIndex.normalizeGamePath(path));
                } catch(IOException ignored) { /* Skip malformed third-party entries */ }
                if(paths.size()>250)throw new IOException("Too many GTA IDE paths");
            }
        }
        int checked=0;
        for(String path:paths) {
            try(Reader input=source.open(path); BufferedReader reader=new BufferedReader(input)) {
                checked++;String section="";String raw;int lines=0;
                while((raw=reader.readLine())!=null) {
                    if(++lines>200000)throw new IOException("IDE file unexpectedly large");
                    String s=clean(raw);
                    if(s.isEmpty())continue;
                    if(s.equalsIgnoreCase("end")){section="";continue;}
                    if(s.indexOf(',')<0){section=s.toLowerCase(Locale.ROOT);continue;}
                    if(!allowedSection(section))continue;
                    String[] parts=s.split(",",-1);
                    if(parts.length<3)continue;
                    String modelName=parts[1].trim().toLowerCase(Locale.ROOT);
                    if(!modelName.equals(wanted))continue;
                    String dict=parts[2].trim().toLowerCase(Locale.ROOT);
                    if(dict.matches("[a-z0-9_.$-]{1,64}"))return new Result(dict,path,checked,paths.size());
                }
            } catch(IOException ignored) {
                // Modded/partial installations can omit an IDE file.
                // Other IDEs must still be scanned.
            }
        }
        return new Result(null,"Model not indexed in GTA IDE",checked,paths.size());
    }
}
