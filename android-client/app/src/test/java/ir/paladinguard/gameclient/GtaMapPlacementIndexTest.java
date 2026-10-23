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
}
