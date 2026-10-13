using System;
using System.Buffers.Binary;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Sockets;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace PGRP.Launcher;

internal sealed class Config
{
    public string GtaExe { get; set; } = "";
    public string Nickname { get; set; } = "";
    public bool LowSpec { get; set; } = true;
}

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        Application.Run(new LauncherWindow());
    }
}

internal sealed class NetPoint
{
    public float X, Y, VX, VY;
}

internal sealed class LauncherWindow : Form
{
    private const string Host = "46.38.138.33";
    private const ushort Port = 7777;
    private static readonly Color BG = Color.FromArgb(10, 14, 21);
    private static readonly Color Nav = Color.FromArgb(13, 18, 26);
    private static readonly Color Card = Color.FromArgb(22, 29, 39);
    private static readonly Color Gold = Color.FromArgb(229, 182, 102);
    private static readonly Color Light = Color.FromArgb(245, 243, 238);
    private static readonly Color Muted = Color.FromArgb(161, 176, 193);
    private static readonly Color Cyan = Color.FromArgb(75, 171, 186);
    private const int HeaderHeight = 63;
    private const int NavWidth = 216;

    private readonly Scene _scene;
    private readonly System.Windows.Forms.Timer _clock = new();
    private readonly System.Windows.Forms.Timer _poll = new();
    private readonly List<NetPoint> _nodes = new();
    private readonly Random _rng = new(38);
    private readonly Dictionary<string, RectangleF> _hits = new();
    private readonly TextBox _nick = new();
    private readonly TextBox _pathBox = new();
    private readonly CheckBox _lowSpec = new();
    private readonly Config _cfg;
    private readonly string _configFile = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "PaladinGuard","Launcher","settings_v054.json");
    private readonly Font _f10 = new("Segoe UI", 10f);
    private readonly Font _f11 = new("Segoe UI", 11f);
    private readonly Font _f12 = new("Segoe UI", 12f);
    private readonly Font _f14b = new("Segoe UI", 14f, FontStyle.Bold);
    private readonly Font _f18b = new("Segoe UI", 18f, FontStyle.Bold);
    private readonly Font _f30b = new("Segoe UI", 30f, FontStyle.Bold);
    private readonly Font _f48b = new("Segoe UI", 48f, FontStyle.Bold);
    private readonly Font _f12b = new("Segoe UI", 12f, FontStyle.Bold);
    private string _page = "home";
    private string _hover = "";
    private string _online = "در حال بررسی";
    private string _population = "— / —";
    private string _latency = "—";
    private bool _busy;
    private Point _mouse;
    private bool _drag;
    private Point _dragPoint;
    private string _lastQuery = "در انتظار اولین پاسخ";
    private int _nodeFrame;
    private int _fps;

    public LauncherWindow()
    {
        FormBorderStyle = FormBorderStyle.None;
        StartPosition = FormStartPosition.CenterScreen;
        MinimumSize = new Size(960, 650);
        ClientSize = new Size(1300, 790);
        BackColor = BG;
        ForeColor = Light;
        Text = "PALADIN GUARD | ROLEPLAY LAUNCHER v0.5.4";
        Font = _f10;
        _cfg = ReadConfig();
        FindGame();
        _scene = new Scene { Dock = DockStyle.Fill };
        Controls.Add(_scene);
        _scene.Paint += PaintScene;
        _scene.MouseMove += MovePointer;
        _scene.MouseLeave += (_, _) => { _hover = ""; _mouse = new Point(-500,-500); };
        _scene.MouseDown += MousePressed;
        _scene.MouseUp += MouseReleased;
        _scene.Resize += (_, _) => LayoutInputs();

        _nick.BorderStyle = BorderStyle.FixedSingle;
        _nick.Font = _f12;
        _nick.BackColor = Color.FromArgb(30, 38, 50);
        _nick.ForeColor = Light;
        _nick.MaxLength = 24;
        _nick.Text = _cfg.Nickname;
        _nick.TextChanged += (_, _) => { _cfg.Nickname = _nick.Text.Trim(); SaveConfig(); };
        _scene.Controls.Add(_nick);

        _pathBox.ReadOnly = true;
        _pathBox.BorderStyle = BorderStyle.FixedSingle;
        _pathBox.BackColor = Color.FromArgb(30, 38, 50);
        _pathBox.ForeColor = Light;
        _pathBox.Font = _f11;
        _pathBox.Text = _cfg.GtaExe;
        _scene.Controls.Add(_pathBox);

        _lowSpec.Text = "حالت سبک (مناسب رم و کارت گرافیک ضعیف)";
        _lowSpec.ForeColor = Light;
        _lowSpec.BackColor = Card;
        _lowSpec.Font = _f11;
        _lowSpec.Checked = _cfg.LowSpec;
        _lowSpec.CheckedChanged += (_, _) => {
            _cfg.LowSpec = _lowSpec.Checked;
            SaveConfig();
            _clock.Interval = _cfg.LowSpec ? 66 : 33;
        };
        _scene.Controls.Add(_lowSpec);

        for (int i = 0; i < 42; i++) AddNode();
        _clock.Interval = _cfg.LowSpec ? 66 : 33;
        _clock.Tick += (_, _) => {
            if (WindowState == FormWindowState.Minimized) return;
            StepNetwork();
            _scene.Invalidate();
        };
        _clock.Start();
        _poll.Interval = 12000;
        _poll.Tick += async (_, _) => await QueryAsync();
        _poll.Start();
        Shown += async (_, _) => await QueryAsync();
        FormClosing += (_, _) => { _clock.Stop(); _poll.Stop(); SaveConfig(); };
        LayoutInputs();
    }

    private sealed class Scene : Control
    {
        public Scene()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            UpdateStyles();
            BackColor = BG;
            TabStop = true;
        }
    }

    private Config ReadConfig()
    {
        try {
            if (File.Exists(_configFile))
                return JsonSerializer.Deserialize<Config>(File.ReadAllText(_configFile)) ?? new Config();
        } catch { }
        return new Config();
    }

    private void SaveConfig()
    {
        try {
            Directory.CreateDirectory(Path.GetDirectoryName(_configFile)!);
            File.WriteAllText(_configFile, JsonSerializer.Serialize(_cfg));
        } catch { }
    }

    private void FindGame()
    {
        if (ValidGame(_cfg.GtaExe)) return;
        var baseDir = Path.Combine(Environment.GetFolderPath(
            Environment.SpecialFolder.LocalApplicationData), "PaladinGuard");
        foreach(var version in new[]{"0.5.4","0.5.3","0.5.2","0.5.1"})
        {
            var candidate = Path.Combine(baseDir, "PGRP_Alpha_v" + version,
                "GTA_San_Andreas", "gta_sa.exe");
            if (!ValidGame(candidate)) continue;
            _cfg.GtaExe = candidate;
            SaveConfig();
            return;
        }
    }

    private static bool ValidGame(string path)
    {
        if (string.IsNullOrWhiteSpace(path) || !File.Exists(path) ||
            !Path.GetFileName(path).Equals("gta_sa.exe", StringComparison.OrdinalIgnoreCase)) return false;
        var root = Path.GetDirectoryName(path)!;
        return File.Exists(Path.Combine(root,"opensamp.exe")) &&
               File.Exists(Path.Combine(root,"Client.Native.dll")) &&
               Directory.Exists(Path.Combine(root,"models")) &&
               Directory.Exists(Path.Combine(root,"data"));
    }

    private string VersionDisplay()
    {
        if (!ValidGame(_cfg.GtaExe)) return "هنوز مسیر نسخه نصب‌شده انتخاب نشده";
        var manifest = Path.GetFullPath(Path.Combine(Path.GetDirectoryName(_cfg.GtaExe)!,
            "..","PGRP_Installed_Version.txt"));
        try { if(File.Exists(manifest)) return File.ReadLines(manifest).FirstOrDefault() ?? "PGRP installed"; }
        catch { }
        return "PGRP | client files detected";
    }

    private void LayoutInputs()
    {
        if (_scene.IsDisposed) return;
        float x = NavWidth + 60;
        int y = HeaderHeight + 148;
        int right = _scene.Width - 75;
        int available = Math.Max(420, right - (int)x);
        _pathBox.Bounds = new Rectangle((int)x + 18,y, Math.Min(available - 190,670),34);
        _nick.Bounds = new Rectangle((int)x + 18,y + 112, Math.Min(390,available - 30),34);
        _lowSpec.Bounds = new Rectangle((int)x + 18,y + 205,Math.Min(570,available - 30),45);
        _pathBox.Visible = _nick.Visible = _lowSpec.Visible = _page == "settings";
    }

    private void ShowPage(string page)
    {
        _page = page;
        LayoutInputs();
        _scene.Invalidate();
    }

    private void AddNode(PointF? near=null)
    {
        float x = near.HasValue ? near.Value.X + _rng.Next(-45,46) : _rng.Next(NavWidth+35,Math.Max(NavWidth+36,_scene.Width-18));
        float y = near.HasValue ? near.Value.Y + _rng.Next(-45,46) : _rng.Next(HeaderHeight+17,Math.Max(HeaderHeight+18,_scene.Height-16));
        _nodes.Add(new NetPoint {
            X = Math.Clamp(x / Math.Max(960,_scene.Width),0.02f,0.98f),
            Y = Math.Clamp(y / Math.Max(650,_scene.Height),0.05f,0.96f),
            VX = ((float)_rng.NextDouble()-0.5f)*0.0004f,
            VY = ((float)_rng.NextDouble()-0.5f)*0.0004f
        });
        if (_nodes.Count > 48) _nodes.RemoveAt(0);
    }

    private void StepNetwork()
    {
        float w=Math.Max(_scene.Width,1), h=Math.Max(_scene.Height,1);
        bool active=_scene.ClientRectangle.Contains(_mouse);
        float contentX=NavWidth+23;
        float contentW=w-contentX-22;
        float hy=HeaderHeight+25;
        float hh=Math.Max(250,Math.Min(320,h*0.40f));
        var heroNet=new RectangleF(contentX+contentW*0.56f+15,hy+10,
            contentW*0.44f-25,hh-20);
        bool onHero=heroNet.Contains(_mouse);
        float netW=onHero?heroNet.Width:w,netH=onHero?heroNet.Height:h;
        foreach(var p in _nodes)
        {
            float x=onHero ? heroNet.X+p.X*heroNet.Width : p.X*w;
            float y=onHero ? heroNet.Y+p.Y*heroNet.Height : p.Y*h;
            if(active)
            {
                float dx=x-_mouse.X,dy=y-_mouse.Y,dist2=dx*dx+dy*dy;
                if(dist2<190*190 && dist2>10)
                {
                    float inv=1f/MathF.Sqrt(dist2);
                    float repulse=(190-MathF.Sqrt(dist2))*0.014f;
                    p.VX+=dx*inv*repulse/netW*0.23f;
                    p.VY+=dy*inv*repulse/netH*0.23f;
                }
            }
            p.VX=Math.Clamp(p.VX*0.97f,-0.0017f,0.0017f);
            p.VY=Math.Clamp(p.VY*0.97f,-0.0017f,0.0017f);
            p.X+=p.VX; p.Y+=p.VY;
            if(p.X<0.02f || p.X>0.98f) p.VX=-p.VX;
            if(p.Y<0.08f || p.Y>0.94f) p.VY=-p.VY;
            p.X=Math.Clamp(p.X,0.02f,0.98f);
            p.Y=Math.Clamp(p.Y,0.08f,0.94f);
        }
        ++_nodeFrame;
    }

    private void MousePressed(object? sender,MouseEventArgs e)
    {
        if(e.Button!=MouseButtons.Left) return;
        if(e.Y<HeaderHeight && e.X>250 && e.X<Width-122)
        {
            _drag=true; _dragPoint=e.Location;
        }
    }
    private void MovePointer(object? sender,MouseEventArgs e)
    {
        _mouse=e.Location;
        if(_drag && e.Button==MouseButtons.Left)
        {
            Left+=e.X-_dragPoint.X;
            Top+=e.Y-_dragPoint.Y;
            return;
        }
        var target=_hits.FirstOrDefault(k=>k.Value.Contains(e.Location)).Key ?? "";
        _hover=target;
        _scene.Cursor = target.Length>0 ? Cursors.Hand : Cursors.Default;
    }
    private void MouseReleased(object? sender,MouseEventArgs e)
    {
        bool dragging=_drag;
        _drag=false;
        if(e.Button!=MouseButtons.Left || dragging) return;
        var action=_hits.FirstOrDefault(k=>k.Value.Contains(e.Location)).Key ?? "";
        switch(action)
        {
            case "minimize": WindowState=FormWindowState.Minimized; break;
            case "close": Close(); break;
            case "home": case "news": case "settings": ShowPage(action); break;
            case "play": Play(); break;
            case "browse": BrowseGame(); break;
            case "save": SaveConfig(); MessageBox.Show(this,"تنظیمات ذخیره شد.","PGRP"); break;
            case "retry": _ = QueryAsync(); break;
            case "guide": ShowPage("guide"); break;
            default:
                // Background interaction: bounded recycling, never accumulation.
                if(e.X>NavWidth && e.Y>HeaderHeight)
                {
                    for(int i=0;i<4;i++) {
                        if(_nodes.Count>0) _nodes.RemoveAt(0);
                        AddNode(e.Location);
                    }
                }
                break;
        }
    }

    private void BrowseGame()
    {
        using var pick=new OpenFileDialog {
            Title="Select installed Paladin Guard GTA San Andreas gta_sa.exe",
            Filter="GTA San Andreas (gta_sa.exe)|gta_sa.exe",
            CheckFileExists=true
        };
        if(pick.ShowDialog(this)!=DialogResult.OK)return;
        if(!ValidGame(pick.FileName))
        {
            MessageBox.Show(this,"مسیر باید پوشه نسخه نصب‌شده PGRP باشد و opensamp.exe و Client.Native.dll را داشته باشد.",
                "مسیر نامعتبر",MessageBoxButtons.OK,MessageBoxIcon.Warning);
            return;
        }
        _cfg.GtaExe=pick.FileName;
        _pathBox.Text=pick.FileName;
        SaveConfig(); _scene.Invalidate();
    }

    private void Play()
    {
        if(!Regex.IsMatch(_cfg.Nickname,@"^[A-Za-z][A-Za-z0-9]*_[A-Za-z][A-Za-z0-9_]*$") ||
           _cfg.Nickname.Length>24)
        {
            ShowPage("settings");
            MessageBox.Show(this,"نام شخصیت باید مانند Ali_McClellan باشد. نام و نام خانوادگی را با _ جدا کن.",
                "نام شخصیت",MessageBoxButtons.OK,MessageBoxIcon.Warning);
            return;
        }
        if(!ValidGame(_cfg.GtaExe))
        {
            ShowPage("settings");
            MessageBox.Show(this,"ابتدا مسیر GTA نصب‌شده در PGRP را مشخص کن.",
                "فایل‌های بازی پیدا نشد",MessageBoxButtons.OK,MessageBoxIcon.Warning);
            return;
        }
        try
        {
            var root=Path.GetDirectoryName(_cfg.GtaExe)!;
            var psi=new ProcessStartInfo(Path.Combine(root,"opensamp.exe")) {
                WorkingDirectory=root,UseShellExecute=false
            };
            psi.Environment["PGRP_AUTOCONNECT_NICK"]=_cfg.Nickname;
            if(Process.Start(psi)==null) throw new IOException("شروع پردازش بازی ناموفق بود");
            // On low-spec PCs free our CPU, RAM and GDI handles after launching.
            Close();
        }
        catch(Exception ex) {
            MessageBox.Show(this,ex.Message,"خطا در اجرای بازی",
                MessageBoxButtons.OK,MessageBoxIcon.Error);
        }
    }

    private async Task QueryAsync()
    {
        if(_busy || IsDisposed) return;
        _busy=true;
        try
        {
            var ip=IPAddress.Parse(Host);
            using var udp=new UdpClient(AddressFamily.InterNetwork);
            byte[] query=new byte[11];
            byte[] address=ip.GetAddressBytes();
            query[0]=(byte)'S';query[1]=(byte)'A';query[2]=(byte)'M';query[3]=(byte)'P';
            Array.Copy(address,0,query,4,4);
            BinaryPrimitives.WriteUInt16LittleEndian(query.AsSpan(8),Port);
            query[10]=(byte)'i';
            var watch=Stopwatch.StartNew();
            await udp.SendAsync(query,query.Length,new IPEndPoint(ip,Port));
            var receive=udp.ReceiveAsync();
            if(await Task.WhenAny(receive,Task.Delay(1800))!=receive)
                throw new TimeoutException("UDP query timeout");
            var response=(await receive).Buffer;
            watch.Stop();
            if(response.Length<16 || response[0]!='S'||response[1]!='A'||
                response[2]!='M'||response[3]!='P'||response[10]!='i')
                throw new InvalidDataException("Bad SA-MP UDP query");
            int online=BinaryPrimitives.ReadUInt16LittleEndian(response.AsSpan(12));
            int cap=BinaryPrimitives.ReadUInt16LittleEndian(response.AsSpan(14));
            _online="آنلاین";
            _population=$"{online} / {cap}";
            _latency=$"{watch.ElapsedMilliseconds} ms";
            _lastQuery="اطلاعات زنده از پاسخ UDP سرور";
        }
        catch
        {
            _online="پاسخ نامشخص";
            _population="— / —";_latency="—";
            _lastQuery="سرور به UDP Query پاسخ نداده؛ لزوماً آفلاین نیست";
        }
        finally
        {
            _busy=false;
            if(!IsDisposed) _scene.Invalidate();
        }
    }

    private static GraphicsPath Round(RectangleF r,float rad)
    {
        var p=new GraphicsPath();
        float d=rad*2f;
        p.AddArc(r.Left,r.Top,d,d,180,90);
        p.AddArc(r.Right-d,r.Top,d,d,270,90);
        p.AddArc(r.Right-d,r.Bottom-d,d,d,0,90);
        p.AddArc(r.Left,r.Bottom-d,d,d,90,90);
        p.CloseFigure();return p;
    }

    private void Rect(Graphics g,RectangleF r,Color fill,Color? border=null,float radius=14)
    {
        using var p=Round(r,radius);
        using var b=new SolidBrush(fill);
        g.FillPath(b,p);
        if(border.HasValue) {using var line=new Pen(border.Value,1);g.DrawPath(line,p);}
    }

    private void TXT(Graphics g,string t,Font font,Color c,float x,float y,float w,float h,
                     bool right=false,bool center=false)
    {
        using var brush=new SolidBrush(c);
        using var sf=new StringFormat(StringFormatFlags.NoWrap);
        sf.Trimming=StringTrimming.EllipsisCharacter;
        sf.LineAlignment=StringAlignment.Center;
        sf.Alignment=center?StringAlignment.Center:right?StringAlignment.Far:StringAlignment.Near;
        if(right) sf.FormatFlags|=StringFormatFlags.DirectionRightToLeft;
        g.DrawString(t,font,brush,new RectangleF(x,y,w,h),sf);
    }

    private void Hit(string id,RectangleF r){_hits[id]=r;}
    private void Button(Graphics g,string id,string title,RectangleF r,bool prominent=false)
    {
        bool on=_hover==id;
        Color fill=prominent ? (on?Color.FromArgb(245,200,130):Gold)
                           : (on?Color.FromArgb(51,65,76):Color.FromArgb(34,44,58));
        Rect(g,r,fill,prominent?Gold:Color.FromArgb(72,90,101),11);
        TXT(g,title,_f12b,prominent?Nav:Light,r.X+10,r.Y,r.Width-20,r.Height,center:true);
        Hit(id,r);
    }

    private void PaintScene(object? sender,PaintEventArgs e)
    {
        var g=e.Graphics;
        g.SmoothingMode=SmoothingMode.AntiAlias;
        g.TextRenderingHint=TextRenderingHint.ClearTypeGridFit;
        int w=_scene.Width,h=_scene.Height;
        if(w<1 || h<1)return;
        using(var bg=new LinearGradientBrush(new Rectangle(0,0,w,h),
            Color.FromArgb(12,17,25),Color.FromArgb(22,30,40),
            LinearGradientMode.Horizontal))
            g.FillRectangle(bg,0,0,w,h);

        DrawNetwork(g,w,h);
        _hits.Clear();
        DrawChrome(g,w,h);
        if(_page=="home") DrawHome(g,w,h);
        else if(_page=="settings") DrawSettings(g,w,h);
        else if(_page=="news") DrawNews(g,w,h);
        else DrawGuide(g,w,h);
    }

    private void DrawNetwork(Graphics g,int w,int h)
    {
        using var line=new Pen(Color.FromArgb(73,194,145,76),1);
        using var faint=new Pen(Color.FromArgb(37,56,156,178),1);
        using var glow=new SolidBrush(Color.FromArgb(184,238,195,120));
        using var pale=new SolidBrush(Color.FromArgb(138,95,193,204));
        var arr=_nodes;
        for(int i=0;i<arr.Count;i++)
        {
            var a=arr[i];float x=a.X*w,y=a.Y*h;
            for(int j=i+1;j<arr.Count;j++)
            {
                var b=arr[j];float dx=x-b.X*w,dy=y-b.Y*h;
                float dist=dx*dx+dy*dy;
                if(dist<190*190)g.DrawLine((i+j)%4==0?faint:line,x,y,b.X*w,b.Y*h);
            }
            g.FillEllipse(i%6==0?pale:glow,x-2.5f,y-2.5f,5,5);
        }
    }

    // Network visible INSIDE the hero, even where other cards are opaque.
    // Draws just 42 pooled nodes and only close neighbor links: inexpensive
    // for old integrated graphics and completely double buffered.
    private void DrawHeroNetwork(Graphics g,RectangleF area)
    {
        var saved=g.Clip;
        g.SetClip(area);
        using var line=new Pen(Color.FromArgb(82,212,164,92),1.05f);
        using var dot=new SolidBrush(Color.FromArgb(201,232,185,110));
        for(int i=0;i<_nodes.Count;i++)
        {
            var a=_nodes[i];
            float ax=area.X+a.X*area.Width;
            float ay=area.Y+a.Y*area.Height;
            for(int j=i+1;j<_nodes.Count;j++)
            {
                var b=_nodes[j];
                float bx=area.X+b.X*area.Width,by=area.Y+b.Y*area.Height;
                float dx=ax-bx,dy=ay-by;
                if(dx*dx+dy*dy<100*100)g.DrawLine(line,ax,ay,bx,by);
            }
            g.FillEllipse(dot,ax-2.2f,ay-2.2f,4.4f,4.4f);
        }
        g.Clip=saved;
    }

    private void DrawChrome(Graphics g,int w,int h)
    {
        g.FillRectangle(new SolidBrush(Color.FromArgb(232,12,17,24)),0,0,NavWidth,h);
        g.FillRectangle(new SolidBrush(Color.FromArgb(249,15,22,30)),0,0,w,HeaderHeight);
        g.FillRectangle(new SolidBrush(Gold),0,0,w,3);
        TXT(g,"PALADIN GUARD",_f14b,Gold,24,15,330,38);
        TXT(g,"ROLEPLAY  /  OFFICIAL CLIENT",_f10,Muted,NavWidth+25,16,470,30);
        TXT(g,"v0.5.4  |  WINDOWS",_f10,Muted,w-365,16,210,30);
        Button(g,"minimize","—",new RectangleF(w-106,15,38,36));
        Button(g,"close","×",new RectangleF(w-60,15,42,36));
        TXT(g,"P G R P",_f30b,Gold,24,84,175,74);
        TXT(g,"PALADIN GUARD",_f12b,Light,26,161,175,24);
        TXT(g,"BUILD YOUR LEGACY",_f10,Muted,26,188,173,24);
        TXT(g,"CONTROL CENTER",_f10,Gold,26,270,173,23);
        string[] ids={"home","news","settings","guide"};
        string[] names={"داشبورد","اطلاعیه‌ها","تنظیمات","راهنمای ورود"};
        for(int i=0;i<ids.Length;i++)
        {
            var r=new RectangleF(15,309+i*60,186,48);
            bool active=_page==ids[i],over=_hover==ids[i];
            Rect(g,r,active?Color.FromArgb(75,57,39):
                     over?Color.FromArgb(44,55,66):Color.FromArgb(23,31,41),
                active?Gold:Color.FromArgb(38,57,66),10);
            if(active)g.FillRectangle(new SolidBrush(Gold),15,322+i*60,3,22);
            TXT(g,names[i],_f11,active?Gold:Light,r.Left+13,r.Top,r.Width-26,r.Height,right:true);
            Hit(ids[i],r);
        }
        TXT(g,"ENGINE  /  open.mp",_f10,Muted,22,h-105,178,25);
        TXT(g,"PGRP WINDOWS 0.5.4",_f10,Gold,22,h-78,178,25);
        TXT(g,"LOW-SPEC READY",_f10,Cyan,22,h-51,178,25);
    }

    private void DrawHome(Graphics g,int w,int h)
    {
        float x=NavWidth+23, available=w-x-22;
        float heroY=HeaderHeight+25,heroH=Math.Max(250,Math.Min(320,h*0.40f));
        var hero=new RectangleF(x,heroY,available,heroH);
        Rect(g,hero,Color.FromArgb(240,22,30,41),Color.FromArgb(105,152,125,73),21);
        float visualX=x+available*0.56f;
        DrawHeroNetwork(g,new RectangleF(visualX+15,heroY+10,
            hero.Right-visualX-25,heroH-20));
        // Integrated bright geometric motif instead of a pasted stock image:
        // non-animated single-pass 2D vector art; GPU textures/shaders not needed.
        using(var ring=new Pen(Color.FromArgb(126,227,180,102),2.0f))
        using(var ring2=new Pen(Color.FromArgb(61,227,180,102),1.2f))
        {
            float cx=visualX+(available*0.44f)*0.49f,cy=heroY+heroH*0.52f;
            float r=Math.Min(heroH*0.37f,available*0.17f);
            g.DrawEllipse(ring,cx-r,cy-r,r*2,r*2);
            g.DrawEllipse(ring2,cx-r-23,cy-r-23,(r+23)*2,(r+23)*2);
            g.DrawLine(ring2,cx-r-55,cy,cx+r+55,cy);
            g.DrawLine(ring2,cx,cy-r-55,cx,cy+r+55);
            TXT(g,"PGRP",_f48b,Gold,cx-r-8,cy-54,r*2+16,102,center:true);
        }
        g.FillRectangle(new SolidBrush(Color.FromArgb(105,213,170,99)),visualX+10,heroY+25,2,heroH-50);
        float leftW=available*0.52f;
        TXT(g,"PALADIN GUARD  /  ROLEPLAY",_f12b,Gold,x+32,heroY+18,leftW-30,35);
        TXT(g,"به قلمرو پالادین خوش آمدی",_f30b,Light,x+31,heroY+65,leftW-35,70,right:true);
        TXT(g,"یک دنیای اختصاصی، یک هویت، ماجراجویی بدون محدودیت",_f11,Muted,x+32,heroY+143,leftW-38,43,right:true);
        float btnY=heroY+heroH-85;
        Button(g,"play","▶   ورود به سرور",new RectangleF(x+33,btnY,Math.Max(186,leftW*0.50f),53),true);
        Button(g,"settings","تنظیمات بازی",new RectangleF(x+48+Math.Max(186,leftW*0.50f),btnY,Math.Max(132,leftW*0.34f),53));
        float y=hero.Bottom+21;
        float gap=15,cardW=(available-2*gap)/3f;
        var cards=new[]{("وضعیت سرور",_online),("بازیکنان آنلاین",_population),("پینگ فعلی",_latency)};
        for(int i=0;i<3;i++)
        {
            var r=new RectangleF(x+i*(cardW+gap),y,cardW,106);
            Rect(g,r,Color.FromArgb(238,22,31,42),Color.FromArgb(68,84,103),15);
            TXT(g,cards[i].Item1,_f11,Muted,r.X+19,r.Y+13,r.Width-38,25,right:true);
            TXT(g,cards[i].Item2,_f18b,i==0?Gold:Light,r.X+19,r.Y+45,r.Width-38,42,right:true);
        }
        float lowerY=y+122,lowerH=Math.Max(90,h-lowerY-25);
        var left=new RectangleF(x,lowerY,available*0.59f-8,lowerH);
        var right=new RectangleF(x+available*0.59f+7,lowerY,available*0.41f-7,lowerH);
        Rect(g,left,Color.FromArgb(235,21,30,40),Color.FromArgb(68,84,103),15);
        Rect(g,right,Color.FromArgb(235,21,30,40),Color.FromArgb(68,84,103),15);
        TXT(g,"نسخه کلاینت",_f12b,Gold,left.X+20,left.Y+13,left.Width-40,28,right:true);
        TXT(g,VersionDisplay(),_f11,Light,left.X+20,left.Y+53,left.Width-40,32,right:true);
        TXT(g,"پروتکل اصلی شبکه: open.mp / SA-MP",_f10,Muted,left.X+20,left.Y+92,left.Width-40,26,right:true);
        TXT(g,"اطلاعیه و وضعیت اتصال",_f12b,Gold,right.X+20,right.Y+13,right.Width-40,29,right:true);
        TXT(g,_lastQuery,_f10,Light,right.X+20,right.Y+54,right.Width-40,54,right:true);
        if(lowerH>148)Button(g,"retry","↻  بروزرسانی",new RectangleF(right.Right-182,right.Bottom-57,160,40));
    }

    private void DrawNews(Graphics g,int w,int h)
    {
        float x=NavWidth+34,ww=w-x-35,y=HeaderHeight+35;
        HeaderPanel(g,"اطلاعیه‌های پالادین گارد","NEWS / UPDATES",x,y,ww);
        var r=new RectangleF(x,y+118,ww,255);
        Rect(g,r,Color.FromArgb(231,21,30,41),Color.FromArgb(88,107,116),17);
        TXT(g,"آخرین اطلاعیه‌ها",_f18b,Gold,x+28,y+136,ww-56,46,right:true);
        TXT(g,"اطلاعیه رسمی فقط بعد از اتصال به سرویس انتشار نمایش داده می‌شود.",_f12,Light,
            x+28,y+210,ww-56,40,right:true);
        TXT(g,"این صفحه فعلاً محتوای آزمایشی ندارد؛ هیچ خبر یا شماره نسخه‌ای به‌عنوان اطلاعات زنده جعل نشده است.",
            _f10,Muted,x+28,y+270,ww-56,55,right:true);
    }

    private void HeaderPanel(Graphics g,string title,string english,float x,float y,float w)
    {
        TXT(g,english,_f12b,Gold,x,y,w,35);
        TXT(g,title,_f30b,Light,x,y+34,w,70,right:true);
    }

    private void DrawSettings(Graphics g,int w,int h)
    {
        float x=NavWidth+34,ww=w-x-35,y=HeaderHeight+27;
        HeaderPanel(g,"تنظیمات بازی","CLIENT / SETTINGS",x,y,ww);
        var card=new RectangleF(x,y+110,ww,355);
        Rect(g,card,Color.FromArgb(235,21,30,40),Color.FromArgb(92,119,125),16);
        TXT(g,"مسیر GTA San Andreas نسخه PGRP",_f12b,Gold,x+27,y+127,ww-54,35,right:true);
        Button(g,"browse","انتخاب مسیر",new RectangleF(x+ww-194,y+168,155,38));
        TXT(g,"نام شخصیت در سرور (Name_Surname)",_f12b,Gold,x+27,y+239,ww-54,35,right:true);
        TXT(g,"برای جلوگیری از مصرف اضافه منابع، لانچر پس از اجرای بازی بسته می‌شود.",_f11,
            Muted,x+30,y+365,ww-60,44,right:true);
        Button(g,"save","ذخیره تنظیمات",new RectangleF(x+27,y+481,210,48),true);
    }

    private void DrawGuide(Graphics g,int w,int h)
    {
        float x=NavWidth+34,ww=w-x-35,y=HeaderHeight+27;
        HeaderPanel(g,"راهنمای ورود","CONNECTION GUIDE",x,y,ww);
        var r=new RectangleF(x,y+116,ww,350);
        Rect(g,r,Color.FromArgb(237,21,31,42),Color.FromArgb(89,112,122),16);
        string[] steps={
            "۱. نسخه GTA San Andreas را با ستاپ اختصاصی PGRP نصب کن.",
            "۲. از قسمت تنظیمات، مسیر فایل gta_sa.exe نسخه نصب‌شده و نام شخصیت را وارد کن.",
            "۳. ورود به سرور را بزن تا ارتباط با 46.38.138.33:7777 برقرار شود.",
            "۴. مراحل احراز هویت داخل بازی را کامل کن. مکان ورود را سرور تعیین می‌کند."
        };
        for(int i=0;i<steps.Length;i++)
        {
            float yy=r.Y+29+i*75;
            Rect(g,new RectangleF(r.X+23,yy,r.Width-46,56),Color.FromArgb(40,47,59),null,9);
            TXT(g,steps[i],_f12,Light,r.X+45,yy+4,r.Width-90,48,right:true);
        }
        Button(g,"home","بازگشت به داشبورد",new RectangleF(x+30,y+500,220,47),true);
    }

    protected override void Dispose(bool disposing)
    {
        if(disposing) {
            _clock?.Dispose();_poll?.Dispose();
            _f10.Dispose();_f11.Dispose();_f12.Dispose();_f14b.Dispose();
            _f18b.Dispose();_f30b.Dispose();_f48b.Dispose();_f12b.Dispose();
        }
        base.Dispose(disposing);
    }
}
