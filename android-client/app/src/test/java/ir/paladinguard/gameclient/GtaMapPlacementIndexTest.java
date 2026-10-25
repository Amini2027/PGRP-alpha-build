package ir.paladinguard.gameclient;

import org.junit.Test;
import java.io.IOException;
import java.io.StringReader;
import java.util.HashMap;
import java.util.Map;
import static org.junit.Assert.*;

public class GtaMapPlacementIndexTest {
    private GtaMapPlacementIndex.Result fixture() throws Exception {
        String manifest="IDE DATA\\MAPS\\LA\\LAe.IDE\n"+
            "IPL DATA\\MAPS\\LA\\LAe.IPL\n"+
            "IPL DATA\\MAPS\\LA\\LAe.IPL\n";
        Map<String,String> data=new HashMap<>();
        data.put("data/maps/la/lae.ide","objs\n1500, actual_road_01, roadtex, 1, 300, 0\nend\n");
        data.put("data/maps/la/lae.ipl","inst\n"+
            "1500, actual_road_01, 0, 1480.0, -1722.0, 20.5, 0, 0, 0, 1, -1\n"+
            "1500, test_int, 1, 1480, -1722, 30, 0,0,0,1,-1\nend\n");
        return GtaMapPlacementIndex.read(new StringReader(manifest),path->{
            String contents=data.get(path);
            return contents==null?null:new StringReader(contents);
        });
    }

    @Test public void readsRealCoordinatesAndLinksModelNames() throws Exception {
        GtaMapPlacementIndex.Result r=fixture();
        assertEquals(1,r.idePaths);
        assertEquals(1,r.iplPaths);
        assertEquals(1,r.ideLoaded);
        assertEquals(1,r.iplLoaded);
        assertEquals(2,r.instances);
        assertEquals(1,r.definitions);
        assertEquals(1,r.nearbyOutside);
        assertEquals(1,r.visibleSamples.size());
        assertEquals("actual_road_01",r.visibleSamples.get(0).modelName);
        assertEquals(1480f,r.visibleSamples.get(0).x,.001f);
        assertEquals(-1722f,r.visibleSamples.get(0).y,.001f);
        assertEquals(20.5f,r.visibleSamples.get(0).z,.001f);
    }

    @Test public void rejectsPathTraversalAndAbsolutePaths() {
        for(String path:new String[]{"../data/maps/a.ipl","data/../maps/a.ipl",
              "models/gta3.img","C:/data/maps/a.ipl","data//maps/a.ipl"}){
            try{
                GtaMapPlacementIndex.normalizeGamePath(path);
                fail("Unsafe path accepted: "+path);
            }catch(IOException expected){}
        }
    }

    @Test public void missingFilesAreReportedWithoutCrashing() throws Exception {
        GtaMapPlacementIndex.Result r=GtaMapPlacementIndex.read(
            new StringReader("IPL DATA\\MAPS\\OTHER\\MISSING.IPL\n"),
            path->{throw new IOException("No file");});
        assertEquals(1,r.iplPaths);
        assertEquals(0,r.iplLoaded);
        assertEquals(1,r.missingFiles);
        assertFalse(r.sampleErrors.isEmpty());
    }

    @Test public void corruptQuaternionAndCoordinatesRejected() throws Exception {
        GtaMapPlacementIndex.Result r=GtaMapPlacementIndex.read(
            new StringReader("IPL DATA\\MAPS\\TEST.IPL\n"),
            path->new StringReader("inst\n"+
                "42, object, 0, NaN, -1722, 0, 0,0,0,1,-1\n"+
                "42, object, 0, 1450, -1700, 0, 0,0,0,1,-1\nend\n"));
        assertEquals(1,r.instances);
        assertEquals(1,r.invalidRecords);
        assertEquals(1,r.visibleSamples.size());
    }
    @Test public void skipsRealGtaZoneMetadataWithoutAbortingIplMapScan() throws Exception {
        // Real GTA SA data/gta.dat lists .ZON pseudo IPL resources.
        // v0.4 threw "Only GTA data IPL/IDE can be read" on these entries.
        String gtaDat =
            "IPL DATA\\MAP.ZON\n"+
            "IPL DATA\\INFO.ZON\n"+
            "IDE DATA\\DEFAULT.IDE\n"+
            "IPL DATA\\MAPS\\LA\\LAe.IPL\n"+
            "IPL DATA\\MAPS\\LA\\LAe.IPL\n";
        java.util.Map<String,String> files = new java.util.HashMap<>();
        files.put("data/default.ide",
            "objs\n1500, road_sample, roadtex, 1, 300, 0\nend\n");
        files.put("data/maps/la/lae.ipl",
            "inst\n1500, road_sample, 0, 1450,-1700,20, 0,0,0,1,-1\nend\n");
        GtaMapPlacementIndex.Result result =
            GtaMapPlacementIndex.read(new StringReader(gtaDat),path->{
                String data=files.get(path);
                if(data==null)throw new IOException("File not found: "+path);
                return new StringReader(data);
            });
        assertEquals(1,result.idePaths);
        assertEquals(1,result.iplPaths);
        assertEquals(1,result.ideLoaded);
        assertEquals(1,result.iplLoaded);
        assertEquals(0,result.missingFiles);
        assertEquals(1,result.instances);
        assertEquals(1,result.nearbyOutside);
    }

    @Test public void skipsOtherNonPlacementResourcesButRejectsIplTraversal() throws Exception {
        String gtaDat="IPL DATA\\VEGAS.ZON\n"+
            "IDE DATA\\INVALID.BIN\n"+
            "IPL DATA\\MAPS\\LA\\GOOD.IPL\n";
        GtaMapPlacementIndex.Result result=GtaMapPlacementIndex.read(
            new StringReader(gtaDat),
            path->new StringReader("inst\n100, test, 0, 1450,-1700,0,0,0,0,1,-1\nend\n"));
        assertEquals(0,result.idePaths);
        assertEquals(1,result.iplPaths);
        assertEquals(1,result.instances);
        try {
            GtaMapPlacementIndex.read(new StringReader("IPL DATA\\..\\evil.ipl\n"),
                path->new StringReader(""));
            fail("Unsafe path accepted");
        }catch(IOException expected){}
    }

}
