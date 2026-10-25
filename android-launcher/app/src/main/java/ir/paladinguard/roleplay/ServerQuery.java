package ir.paladinguard.roleplay;

import java.io.IOException;
import java.net.DatagramPacket;
import java.net.DatagramSocket;
import java.net.Inet4Address;
import java.net.InetAddress;
import java.nio.charset.StandardCharsets;

/**
 * Read-only SA-MP/open.mp UDP info query.
 * Never treats an unanswered query as proof that the server is offline:
 * game UDP may be open while SA-MP info queries are disabled or filtered.
 */
public final class ServerQuery {
    public static final String HOST = "46.38.138.33";
    public static final int PORT = 7777;

    public static final class Status {
        public final String hostname;
        public final int players;
        public final int maxPlayers;
        public final boolean passwordProtected;
        public final long pingMs;
        public Status(String hostname, int players, int maxPlayers, boolean passwordProtected, long pingMs) {
            this.hostname = hostname;
            this.players = players;
            this.maxPlayers = maxPlayers;
            this.passwordProtected = passwordProtected;
            this.pingMs = pingMs;
        }
    }

    private ServerQuery() {}

    public static byte[] queryPacket(byte[] ip, int port) {
        if (ip == null || ip.length != 4 || port < 1 || port > 65535) {
            throw new IllegalArgumentException("invalid server address");
        }
        return new byte[]{
            'S','A','M','P',ip[0],ip[1],ip[2],ip[3],
            (byte)(port & 255), (byte)((port >>> 8) & 255), 'i'
        };
    }

    private static int u8(byte[] a, int at) { return a[at] & 0xff; }

    public static Status parseInfo(byte[] packet, int length, byte[] ip, int port, long pingMs) {
        if (packet == null || ip == null || ip.length != 4 || length < 22 || length > packet.length) {
            throw new IllegalArgumentException("invalid reply length");
        }
        if (packet[0]!='S' || packet[1]!='A' || packet[2]!='M' || packet[3]!='P'
            || packet[10]!='i'
            || packet[4]!=ip[0] || packet[5]!=ip[1] || packet[6]!=ip[2] || packet[7]!=ip[3]
            || u8(packet,8)!=(port&255) || u8(packet,9)!=((port >>> 8)&255)) {
            throw new IllegalArgumentException("invalid response header");
        }
        boolean password = packet[11] != 0;
        int players = u8(packet,12) | (u8(packet,13) << 8);
        int maximum = u8(packet,14) | (u8(packet,15) << 8);
        long hostnameLength = ((long)u8(packet,16)) | ((long)u8(packet,17)<<8)
            | ((long)u8(packet,18)<<16) | ((long)u8(packet,19)<<24);
        if (hostnameLength > 512 || 20 + hostnameLength > length) {
            throw new IllegalArgumentException("invalid hostname length");
        }
        if (maximum < 1 || maximum > 10000 || players > maximum) {
            throw new IllegalArgumentException("invalid player count");
        }
        String hostname = new String(packet,20,(int)hostnameLength,StandardCharsets.UTF_8)
            .replaceAll("[\\p{Cntrl}]", "").trim();
        if (hostname.isEmpty()) hostname = "Paladin Guard RolePlay";
        return new Status(hostname, players, maximum, password, pingMs);
    }

    public static Status read() throws IOException {
        final InetAddress addr = InetAddress.getByName(HOST);
        if (!(addr instanceof Inet4Address)) throw new IOException("IPv4 address required");
        final byte[] ip = addr.getAddress();
        final byte[] request = queryPacket(ip, PORT);
        final byte[] buffer = new byte[1024];
        try (DatagramSocket socket = new DatagramSocket()) {
            socket.setSoTimeout(2200);
            long start = System.nanoTime();
            socket.send(new DatagramPacket(request, request.length, addr, PORT));
            DatagramPacket response = new DatagramPacket(buffer, buffer.length);
            socket.receive(response);
            if (!addr.equals(response.getAddress()) || response.getPort() != PORT) {
                throw new IOException("unexpected response source");
            }
            long pingMs = (System.nanoTime() - start) / 1000000;
            try {
                return parseInfo(response.getData(), response.getLength(), ip, PORT, pingMs);
            } catch (IllegalArgumentException invalid) {
                throw new IOException("unrecognized game server reply", invalid);
            }
        }
    }
}
