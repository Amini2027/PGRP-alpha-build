package ir.paladinguard.gameclient;

import java.io.IOException;
import java.net.DatagramPacket;
import java.net.DatagramSocket;
import java.net.Inet4Address;
import java.net.InetAddress;
import java.net.SocketTimeoutException;
import java.nio.charset.StandardCharsets;

/**
 * RakNet/SA-MP UDP transport discovery only.
 *
 * This is NOT an authenticated open.mp game session. A full client still
 * needs reliable RakNet channels, connection negotiation, encryption/version
 * details, SA-MP RPC/dialog/sync handlers and server-side protocol validation.
 */
public final class GameNetworkProbe {
    public static final String SERVER = "46.38.138.33";
    public static final int PORT = 7777;
    private static final byte[] MAGIC={
        0x00,(byte)0xff,(byte)0xff,0x00,(byte)0xfe,(byte)0xfe,(byte)0xfe,(byte)0xfe,
        (byte)0xfd,(byte)0xfd,(byte)0xfd,(byte)0xfd,0x12,0x34,0x56,0x78
    };
    private GameNetworkProbe(){}

    public static byte[] sampInfoRequest(byte[] ip,int port){
        if(ip==null||ip.length!=4||port<1||port>65535)throw new IllegalArgumentException("IPv4/port");
        return new byte[]{'S','A','M','P',ip[0],ip[1],ip[2],ip[3],(byte)port,(byte)(port>>8),'i'};
    }

    public static byte[] rakNetOpenRequest1(int protocolVersion){
        if(protocolVersion<0||protocolVersion>255)throw new IllegalArgumentException("protocol");
        // Zero pad up to a conservative MTU (576) as required by RakNet
        // ID_OPEN_CONNECTION_REQUEST_1. Version 6 is SA-MP 0.3.x candidate,
        // and may differ from the open.mp runtime or server configuration.
        byte[] packet=new byte[576];
        packet[0]=0x05;
        System.arraycopy(MAGIC,0,packet,1,MAGIC.length);
        packet[17]=(byte)protocolVersion;
        return packet;
    }

    public static String parseRakNetReply(byte[] bytes,int length){
        if(bytes==null||length<=0||length>bytes.length)return "پاسخ نامعتبر";
        int type=bytes[0]&255;
        if(type==0x19)return "ناسازگاری نسخه پروتکل RakNet";
        if(type==0x06){
            if(length<18)return "پاسخ ناقص RakNet";
            for(int i=0;i<MAGIC.length;i++)if(bytes[1+i]!=MAGIC[i])return "پاسخ RakNet نامعتبر";
            return "RakNet مرحله اول پاسخ داد؛ ورود به بازی هنوز پیاده نشده";
        }
        return "پاسخ غیرمنتظره UDP (0x"+Integer.toHexString(type)+")";
    }

    public static String pingInfo() throws IOException {
        InetAddress host=InetAddress.getByName(SERVER);
        if(!(host instanceof Inet4Address))throw new IOException("IPv4 required");
        byte[] query=sampInfoRequest(host.getAddress(),PORT);
        try(DatagramSocket socket=new DatagramSocket()){
            socket.setSoTimeout(2300);
            long start=System.nanoTime();
            socket.send(new DatagramPacket(query,query.length,host,PORT));
            byte[] buffer=new byte[1024];
            DatagramPacket response=new DatagramPacket(buffer,buffer.length);
            socket.receive(response);
            if(!host.equals(response.getAddress())||response.getPort()!=PORT)throw new IOException("unexpected source");
            int n=response.getLength();
            byte[] data=response.getData();
            if(n<20||data[0]!='S'||data[1]!='A'||data[2]!='M'||data[3]!='P'
                ||data[10]!='i')throw new IOException("invalid SA-MP query response");
            for(int i=0;i<4;i++)if(data[4+i]!=query[4+i])throw new IOException("unexpected IP in reply");
            if(data[8]!=query[8]||data[9]!=query[9])throw new IOException("unexpected port in reply");
            int online=(data[12]&255)|((data[13]&255)<<8);
            int max=(data[14]&255)|((data[15]&255)<<8);
            long titleLen=(data[16]&255L)|((data[17]&255L)<<8)
                |((data[18]&255L)<<16)|((data[19]&255L)<<24);
            if(titleLen<0||titleLen>512||20+titleLen>n||max<1||online>max)
                throw new IOException("invalid info packet");
            long ms=(System.nanoTime()-start)/1_000_000;
            return "UDP "+ms+"ms  |  "+online+"/"+max+" بازیکن";
        }
    }

    public static String probeRakNetHandshake() throws IOException {
        InetAddress host=InetAddress.getByName(SERVER);
        if(!(host instanceof Inet4Address))throw new IOException("IPv4 required");
        byte[] packet=rakNetOpenRequest1(6);
        try(DatagramSocket socket=new DatagramSocket()){
            socket.setSoTimeout(2300);
            socket.send(new DatagramPacket(packet,packet.length,host,PORT));
            byte[] buffer=new byte[1500];
            DatagramPacket response=new DatagramPacket(buffer,buffer.length);
            socket.receive(response);
            if(!host.equals(response.getAddress())||response.getPort()!=PORT)
                throw new IOException("unexpected server reply");
            return parseRakNetReply(response.getData(),response.getLength());
        }
    }
}
