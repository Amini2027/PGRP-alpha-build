package ir.paladinguard.roleplay;

import org.junit.Test;
import static org.junit.Assert.*;

import java.nio.charset.StandardCharsets;
import java.util.Arrays;

public class ServerQueryTest {
    private final byte[] ip = new byte[]{46,38,(byte)138,33};

    @Test public void queryPacketMatchesSampProtocol() {
        assertArrayEquals(new byte[]{'S','A','M','P',46,38,(byte)138,33,97,30,'i'},
            ServerQuery.queryPacket(ip,7777));
    }

    @Test public void parseValidResponse() {
        byte[] host = "Paladin Guard".getBytes(StandardCharsets.UTF_8);
        byte[] result = new byte[20 + host.length];
        System.arraycopy(ServerQuery.queryPacket(ip,7777),0,result,0,11);
        result[11]=0;
        result[12]=12; result[13]=0; // players little-endian
        result[14]=100; result[15]=0;
        result[16]=(byte)host.length;
        System.arraycopy(host,0,result,20,host.length);
        ServerQuery.Status s=ServerQuery.parseInfo(result,result.length,ip,7777,42);
        assertEquals("Paladin Guard",s.hostname);
        assertEquals(12,s.players);
        assertEquals(100,s.maxPlayers);
        assertEquals(42,s.pingMs);
        assertFalse(s.passwordProtected);
    }

    @Test(expected=IllegalArgumentException.class)
    public void rejectWrongIp() {
        byte[] response=reply("PGRP",5,50);
        ServerQuery.parseInfo(response,response.length,new byte[]{127,0,0,1},7777,1);
    }

    @Test(expected=IllegalArgumentException.class)
    public void rejectTruncatedHostname() {
        byte[] response=reply("PGRP",5,50);
        ServerQuery.parseInfo(response,response.length-1,ip,7777,1);
    }

    @Test(expected=IllegalArgumentException.class)
    public void rejectPlayerCountOverMaximum() {
        byte[] response=reply("PGRP",51,50);
        ServerQuery.parseInfo(response,response.length,ip,7777,1);
    }

    private byte[] reply(String host,int current,int max) {
        byte[] bytes=host.getBytes(StandardCharsets.UTF_8);
        byte[] packet=new byte[20+bytes.length];
        System.arraycopy(ServerQuery.queryPacket(ip,7777),0,packet,0,11);
        packet[12]=(byte)current; packet[13]=(byte)(current>>8);
        packet[14]=(byte)max; packet[15]=(byte)(max>>8);
        packet[16]=(byte)bytes.length;
        System.arraycopy(bytes,0,packet,20,bytes.length);
        return packet;
    }
}
