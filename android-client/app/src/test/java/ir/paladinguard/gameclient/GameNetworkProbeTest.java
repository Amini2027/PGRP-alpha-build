package ir.paladinguard.gameclient;
import org.junit.Test;
import static org.junit.Assert.*;

public class GameNetworkProbeTest {
    @Test public void sampInfoRequestContainsIpAndPort(){
        byte[] ip={46,38,(byte)138,33};
        byte[] packet=GameNetworkProbe.sampInfoRequest(ip,7777);
        assertArrayEquals(new byte[]{'S','A','M','P',46,38,(byte)138,33,97,30,'i'},packet);
    }
    @Test public void raknetOpenRequestHasProtocolVersionMagicAndMtu(){
        byte[] packet=GameNetworkProbe.rakNetOpenRequest1(6);
        assertEquals(576,packet.length);
        assertEquals(5,packet[0]);
        assertEquals((byte)0,packet[1]);
        assertEquals((byte)0xff,packet[2]);
        assertEquals((byte)0x78,packet[16]);
        assertEquals((byte)6,packet[17]);
    }
    @Test public void validRaknetFirstReplyNotMisrepresentedAsFullLogin(){
        byte[] request=GameNetworkProbe.rakNetOpenRequest1(6);
        byte[] reply=new byte[30];
        reply[0]=6;
        System.arraycopy(request,1,reply,1,16);
        String result=GameNetworkProbe.parseRakNetReply(reply,reply.length);
        assertTrue(result.contains("مرحله اول"));
        assertTrue(result.contains("هنوز پیاده نشده"));
    }
    @Test public void truncatedRaknetReplyRejected(){
        assertTrue(GameNetworkProbe.parseRakNetReply(new byte[]{6},1).contains("ناقص"));
    }
    @Test public void invalidRaknetMagicRejected(){
        assertTrue(GameNetworkProbe.parseRakNetReply(new byte[30],30).contains("غیرمنتظره"));
    }
    @Test public void mismatchProtocolHandled(){
        assertTrue(GameNetworkProbe.parseRakNetReply(new byte[]{0x19},1).contains("ناسازگاری"));
    }
}
