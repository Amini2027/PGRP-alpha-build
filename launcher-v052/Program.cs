using System;
using System.Buffers.Binary;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Sockets;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace PGRP.Launcher;

internal sealed class LauncherSettings
{
    public string GtaExecutable { get; set; } = "";
    public string Nickname { get; set; } = "";
    public bool LowSpec { get; set; } = true;
}

internal static class EntryPoint
{
    [STAThread]
    private static void Main()
    {
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        Application.Run(new LauncherWindow());
    }
}

internal sealed class NetworkCanvas : Panel
{
    private sealed class Node
    {
        public float X, Y, Vx, Vy;
    }

    private readonly List<Node> _nodes = new();
    private readonly Random _random = new();
    private bool _lowSpec = true;
    private bool _seeded;

    public NetworkCanvas()
    {
        Dock = DockStyle.Fill;
        BackColor = Color.FromArgb(10, 13, 19);
        DoubleBuffered = true;
        ResizeRedraw = true;
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint |
                 ControlStyles.OptimizedDoubleBuffer, true);
        MouseDown += (_, e) =>
        {
            if (e.Button != MouseButtons.Left) return;
            // Bounded effect: every click refreshes 3 nodes and removes the
            // same number. It never builds an unbounded graph or allocation.
            for (int i = 0; i < 3; i++)
            {
                if (_nodes.Count > 0) _nodes.RemoveAt(0);
                AddNode(e.Location);
            }
        };
    }

    public void SetLowSpec(bool value) => _lowSpec = value;

    protected override void OnSizeChanged(EventArgs e)
    {
        base.OnSizeChanged(e);
        if (!_seeded && Width > 150 && Height > 150)
        {
            _seeded = true;
            for (int i = 0; i < 30; i++) AddNode();
        }
    }

    private void AddNode(Point? near = null)
    {
        float x = near.HasValue
            ? near.Value.X + _random.Next(-85, 86)
            : _random.Next(Math.Max(1, Width));
        float y = near.HasValue
            ? near.Value.Y + _random.Next(-85, 86)
            : _random.Next(Math.Max(1, Height));
        _nodes.Add(new Node
        {
            X = Math.Clamp(x, 8, Math.Max(8, Width - 8)),
            Y = Math.Clamp(y, 8, Math.Max(8, Height - 8)),
            Vx = ((float)_random.NextDouble() - 0.5f) * 0.75f,
            Vy = ((float)_random.NextDouble() - 0.5f) * 0.75f
        });
        if (_nodes.Count > 36) _nodes.RemoveAt(0);
    }

    public void Step()
    {
        if (Width < 10 || Height < 10 || !Visible) return;
        var cursor = PointToClient(Cursor.Position);
        bool inside = ClientRectangle.Contains(cursor);
        float speed = _lowSpec ? 0.45f : 1f;
        foreach (var p in _nodes)
        {
            if (inside)
            {
                float dx = p.X - cursor.X, dy = p.Y - cursor.Y;
                float dist2 = dx * dx + dy * dy;
                if (dist2 > 1f && dist2 < 120f * 120f)
                {
                    float dist = MathF.Sqrt(dist2);
                    float force = (120f - dist) / 120f * 2.6f * speed;
                    p.Vx += dx / dist * force * 0.11f;
                    p.Vy += dy / dist * force * 0.11f;
                }
            }
            p.Vx *= 0.985f;
            p.Vy *= 0.985f;
            p.Vx = Math.Clamp(p.Vx, -1.7f, 1.7f);
            p.Vy = Math.Clamp(p.Vy, -1.7f, 1.7f);
            p.X += p.Vx * speed;
            p.Y += p.Vy * speed;
            if (p.X < 6 || p.X > Width - 6) p.Vx = -p.Vx;
            if (p.Y < 6 || p.Y > Height - 6) p.Vy = -p.Vy;
            p.X = Math.Clamp(p.X, 6, Math.Max(6, Width - 6));
            p.Y = Math.Clamp(p.Y, 6, Math.Max(6, Height - 6));
        }
        Invalidate(); // 13 FPS low-spec, 25 FPS normal: no uncapped redraw loop.
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        using (var bg = new LinearGradientBrush(ClientRectangle,
            Color.FromArgb(12, 15, 23), Color.FromArgb(21, 26, 35), 0f))
            e.Graphics.FillRectangle(bg, ClientRectangle);

        using var connection = new Pen(Color.FromArgb(48, 169, 129, 65), 1f);
        using var dot = new SolidBrush(Color.FromArgb(164, 209, 167, 94));
        int count = _nodes.Count;
        for (int i = 0; i < count; i++)
        {
            var a = _nodes[i];
            for (int j = i + 1; j < count; j++)
            {
                var b = _nodes[j];
                float dx = a.X - b.X, dy = a.Y - b.Y;
                if (dx * dx + dy * dy < 150f * 150f)
                    e.Graphics.DrawLine(connection, a.X, a.Y, b.X, b.Y);
            }
            e.Graphics.FillEllipse(dot, a.X - 2.25f, a.Y - 2.25f, 4.5f, 4.5f);
        }
    }
}

internal sealed class LauncherWindow : Form
{
    private const string Host = "46.38.138.33";
    private const int Port = 7777;
    private static readonly Color Base = Color.FromArgb(13, 17, 24);
    private static readonly Color Card = Color.FromArgb(26, 31, 40);
    private static readonly Color Muted = Color.FromArgb(160, 166, 177);
    private static readonly Color Gold = Color.FromArgb(213, 170, 100);
    private static readonly Color White = Color.FromArgb(242, 241, 235);
    private readonly NetworkCanvas _network = new();
    private readonly System.Windows.Forms.Timer _animation = new();
    private readonly System.Windows.Forms.Timer _refresh = new();
    private readonly Panel _home = new();
    private readonly Panel _news = new();
    private readonly Panel _settings = new();
    private readonly Panel _side = new();
    private readonly Label _status = new();
    private readonly Label _players = new();
    private readonly Label _ping = new();
    private readonly Label _client = new();
    private readonly TextBox _gamePath = new();
    private readonly TextBox _nick = new();
    private readonly CheckBox _lowSpec = new();
    private readonly Dictionary<string, Button> _tabs = new();
    private readonly LauncherSettings _config;
    private bool _checking;
    private string _page = "home";
    private readonly string _settingsPath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "PaladinGuard", "Launcher", "settings.json");

    public LauncherWindow()
    {
        Text = "PALADIN GUARD | ROLEPLAY LAUNCHER";
        ClientSize = new Size(1150, 720);
        MinimumSize = new Size(920, 625);
        StartPosition = FormStartPosition.CenterScreen;
        Font = new Font("Segoe UI", 10f);
        ForeColor = White;
        BackColor = Base;
        DoubleBuffered = true;
        _config = ReadSettings();
        AutoDetectGame();

        Controls.Add(_network);
        _network.SendToBack();
        _network.Controls.Add(_home);
        _network.Controls.Add(_news);
        _network.Controls.Add(_settings);
        BuildSidebar();
        BuildHome();
        BuildNews();
        BuildSettings();

        _animation.Interval = _config.LowSpec ? 75 : 40;
        _network.SetLowSpec(_config.LowSpec);
        _animation.Tick += (_, _) =>
        {
            if (WindowState != FormWindowState.Minimized) _network.Step();
        };
        _animation.Start();

        _refresh.Interval = 12000;
        _refresh.Tick += async (_, _) => await CheckServerAsync();
        _refresh.Start();
        Shown += async (_, _) => await CheckServerAsync();
        Resize += (_, _) => Reflow();
        Reflow();
        ShowPage("home");
        FormClosing += (_, _) => { _animation.Stop(); _refresh.Stop(); SaveSettings(); };
    }

    private static Label Label(string text, int x, int y, int w, int h,
        int size = 11, bool emphasized = false, Color? color = null)
    {
        return new Label
        {
            Text = text,
            Location = new Point(x, y),
            Size = new Size(w, h),
            Font = new Font("Segoe UI", size, emphasized ? FontStyle.Bold : FontStyle.Regular),
            ForeColor = color ?? White,
            BackColor = Color.Transparent,
            TextAlign = ContentAlignment.MiddleLeft
        };
    }

    private static Button Button(string text, int x, int y, int w, int h, bool primary = false)
    {
        var button = new Button
        {
            Text = text, Location = new Point(x, y), Size = new Size(w, h),
            BackColor = primary ? Gold : Color.FromArgb(39, 46, 56),
            ForeColor = primary ? Color.FromArgb(17, 19, 22) : White,
            FlatStyle = FlatStyle.Flat,
            Cursor = Cursors.Hand,
            Font = new Font("Segoe UI", 10.5f, FontStyle.Bold),
            UseVisualStyleBackColor = false
        };
        button.FlatAppearance.BorderColor = primary ? Gold : Color.FromArgb(84, 86, 92);
        button.FlatAppearance.MouseOverBackColor =
            primary ? Color.FromArgb(235, 194, 121) : Color.FromArgb(52, 60, 70);
        return button;
    }

    private static Panel Box(int x, int y, int w, int h)
    {
        var panel = new Panel { Location = new Point(x, y), Size = new Size(w, h), BackColor = Card };
        panel.Paint += (_, e) =>
        {
            using var p = new Pen(Color.FromArgb(66, 170, 137, 81));
            e.Graphics.DrawRectangle(p, 0, 0, panel.Width - 1, panel.Height - 1);
        };
        return panel;
    }

    private void BuildSidebar()
    {
        _side.BackColor = Color.FromArgb(15, 18, 26);
        _side.Width = 225;
        Controls.Add(_side);
        _side.BringToFront();
        _side.Controls.Add(Label("P G R P", 27, 32, 180, 45, 25, true, Gold));
        _side.Controls.Add(Label("PALADIN GUARD", 27, 77, 185, 24, 10, true, White));
        _side.Controls.Add(Label("ROLEPLAY  /  IRAN", 27, 103, 185, 21, 9, false, Muted));
        int top = 182;
        foreach (var pair in new[] { ("home", "صفحه اصلی"), ("news", "اطلاعیه‌ها"), ("settings", "تنظیمات") })
        {
            string key = pair.Item1;
            var btn = Button(pair.Item2, 19, top, 188, 45);
            btn.TextAlign = ContentAlignment.MiddleCenter;
            btn.Click += (_, _) => ShowPage(key);
            _tabs[key] = btn;
            _side.Controls.Add(btn);
            top += 59;
        }
        _side.Controls.Add(Label("PGRP CLIENT  /  WINDOWS", 22, 580, 195, 25, 9, false, Muted));
        _side.Controls.Add(Label("LAUNCHER 0.5.3", 22, 607, 195, 22, 9, false, Gold));
    }

    private void BuildHome()
    {
        _home.BackColor = Color.Transparent;
        _home.AutoScroll = true;
        var hero = Box(18, 17, 535, 290);
        _home.Controls.Add(hero);
        hero.Controls.Add(Label("PALADIN GUARD  /  ROLEPLAY", 30, 24, 445, 27, 12, true, Gold));
        hero.Controls.Add(Label("قلمرو پالادین منتظر توست", 30, 61, 485, 65, 23, true));
        hero.Controls.Add(Label("به سرور اختصاصی رول‌پلی متصل شو و داستان خودت را بساز.", 30, 130, 470, 35, 10, false, Muted));
        var play = Button("▶   ورود به سرور", 29, 199, 260, 52, true);
        play.Click += (_, _) => LaunchGame();
        hero.Controls.Add(play);
        var options = Button("تنظیمات بازی", 303, 199, 198, 52);
        options.Click += (_, _) => ShowPage("settings");
        hero.Controls.Add(options);

        var addresses = Box(571, 17, 275, 290);
        _home.Controls.Add(addresses);
        addresses.Controls.Add(Label("SERVER ENDPOINT", 24, 31, 230, 32, 11, true, Gold));
        addresses.Controls.Add(Label(Host + ":" + Port, 24, 75, 240, 40, 15, true));
        addresses.Controls.Add(Label("پروتکل SA-MP / open.mp", 24, 132, 235, 26, 10, false, Muted));
        addresses.Controls.Add(Label("وضعیت لحظه‌ای از UDP Query", 24, 171, 235, 30, 9, false, Muted));
        var refreshButton = Button("بروزرسانی وضعیت ↻", 24, 224, 227, 41);
        refreshButton.Click += async (_, _) => await CheckServerAsync();
        addresses.Controls.Add(refreshButton);

        var stats = Box(18, 324, 828, 123);
        _home.Controls.Add(stats);
        stats.Controls.Add(Label("وضعیت سرور", 25, 15, 208, 25, 10, false, Muted));
        stats.Controls.Add(Label("بازیکنان", 299, 15, 213, 25, 10, false, Muted));
        stats.Controls.Add(Label("پینگ", 575, 15, 225, 25, 10, false, Muted));
        _status.Location = new Point(25, 44);
        _status.Size = new Size(245, 47);
        _status.Font = new Font("Segoe UI", 17, FontStyle.Bold);
        _status.ForeColor = Gold;
        _status.Text = "در حال بررسی...";
        stats.Controls.Add(_status);
        _players.Location = new Point(299, 44);
        _players.Size = new Size(235, 47);
        _players.Font = new Font("Segoe UI", 17, FontStyle.Bold);
        _players.Text = "— / —";
        stats.Controls.Add(_players);
        _ping.Location = new Point(575, 44);
        _ping.Size = new Size(225, 47);
        _ping.Font = new Font("Segoe UI", 17, FontStyle.Bold);
        _ping.Text = "— ms";
        stats.Controls.Add(_ping);

        var foot = Box(18, 464, 828, 118);
        _home.Controls.Add(foot);
        foot.Controls.Add(Label("وضعیت کلاینت", 25, 18, 195, 29, 12, true, Gold));
        _client.Location = new Point(25, 52);
        _client.Size = new Size(750, 44);
        _client.Font = new Font("Segoe UI", 10.5f);
        _client.ForeColor = White;
        foot.Controls.Add(_client);
    }

    private void BuildNews()
    {
        _news.BackColor = Color.Transparent;
        _news.AutoScroll = true;
        var card = Box(18, 17, 827, 270);
        _news.Controls.Add(card);
        card.Controls.Add(Label("اعلامیه‌ها  /  PGRP NETWORK", 28, 24, 750, 44, 20, true, Gold));
        card.Controls.Add(Label("به قلمرو پالادین گارد خوش آمدید", 28, 95, 740, 43, 16, true));
        card.Controls.Add(Label("اطلاعیه‌های رسمی در نسخه‌های آینده به سرویس انتشار متصل خواهند شد.", 28, 154, 748, 40, 11, false, Muted));
        card.Controls.Add(Label("این متن محلی است و به‌عنوان خبر زنده سرور نمایش داده نمی‌شود.", 28, 211, 748, 30, 10, false, Muted));
    }

    private void BuildSettings()
    {
        _settings.BackColor = Color.Transparent;
        _settings.AutoScroll = true;
        var card = Box(18, 17, 827, 495);
        _settings.Controls.Add(card);
        card.Controls.Add(Label("تنظیمات لانچر", 29, 20, 740, 45, 20, true, Gold));
        card.Controls.Add(Label("مسیر gta_sa.exe نسخه اختصاصی PGRP", 29, 86, 695, 30, 12, true));
        _gamePath.Location = new Point(29, 124);
        _gamePath.Size = new Size(615, 30);
        _gamePath.ReadOnly = true;
        _gamePath.BackColor = Color.FromArgb(36, 43, 51);
        _gamePath.ForeColor = White;
        _gamePath.BorderStyle = BorderStyle.FixedSingle;
        _gamePath.Text = _config.GtaExecutable;
        card.Controls.Add(_gamePath);
        var browse = Button("انتخاب مسیر", 660, 120, 138, 41);
        browse.Click += (_, _) => BrowseGame();
        card.Controls.Add(browse);
        card.Controls.Add(Label("نام شخصیت (Name_Surname)", 29, 200, 425, 27, 12, true));
        _nick.Location = new Point(29, 240);
        _nick.Size = new Size(408, 34);
        _nick.MaxLength = 24;
        _nick.Text = _config.Nickname;
        _nick.BackColor = Color.FromArgb(36, 43, 51);
        _nick.ForeColor = White;
        _nick.BorderStyle = BorderStyle.FixedSingle;
        _nick.TextChanged += (_, _) => { _config.Nickname = _nick.Text.Trim(); SaveSettings(); };
        card.Controls.Add(_nick);
        _lowSpec.Text = "حالت سبک برای سیستم‌های ضعیف (انیمیشن کم‌مصرف)";
        _lowSpec.Checked = _config.LowSpec;
        _lowSpec.Location = new Point(29, 307);
        _lowSpec.Size = new Size(645, 45);
        _lowSpec.ForeColor = White;
        _lowSpec.BackColor = Card;
        _lowSpec.CheckedChanged += (_, _) =>
        {
            _config.LowSpec = _lowSpec.Checked;
            _animation.Interval = _lowSpec.Checked ? 75 : 40;
            _network.SetLowSpec(_lowSpec.Checked);
            SaveSettings();
        };
        card.Controls.Add(_lowSpec);
        var save = Button("ذخیره تنظیمات", 29, 397, 243, 48, true);
        save.Click += (_, _) => { SaveSettings(); MessageBox.Show(this, "تنظیمات ذخیره شد.", "PGRP"); };
        card.Controls.Add(save);
        card.Controls.Add(Label("نسخه کلاینت از پوشه نصب تشخیص داده می‌شود؛ فایل GTA کپی یا دستکاری نمی‌شود.", 294, 397, 490, 49, 10, false, Muted));
    }

    private void Reflow()
    {
        _side.Height = ClientSize.Height;
        _home.Bounds = new Rectangle(239, 105, Math.Max(680, ClientSize.Width - 258), 598);
        _news.Bounds = _home.Bounds;
        _settings.Bounds = _home.Bounds;
    }

    private void ShowPage(string page)
    {
        _page = page;
        _home.Visible = page == "home";
        _news.Visible = page == "news";
        _settings.Visible = page == "settings";
        foreach (var p in _tabs)
        {
            bool active = p.Key == page;
            p.Value.BackColor = active ? Color.FromArgb(94, 70, 43) : Color.FromArgb(39, 46, 56);
            p.Value.FlatAppearance.BorderColor = active ? Gold : Color.FromArgb(84, 86, 92);
        }
        UpdateClientLabel();
    }

    private LauncherSettings ReadSettings()
    {
        try
        {
            if (File.Exists(_settingsPath))
                return JsonSerializer.Deserialize<LauncherSettings>(File.ReadAllText(_settingsPath))
                    ?? new LauncherSettings();
        }
        catch { /* Keep app usable if old settings are invalid. */ }
        return new LauncherSettings();
    }

    private void SaveSettings()
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(_settingsPath)!);
            File.WriteAllText(_settingsPath, JsonSerializer.Serialize(_config));
        }
        catch { /* Settings errors surface again when the user selects Play. */ }
    }

    private void AutoDetectGame()
    {
        if (IsGameReady(_config.GtaExecutable)) return;
        var root = Path.Combine(Environment.GetFolderPath(
            Environment.SpecialFolder.LocalApplicationData), "PaladinGuard");
        foreach (var version in new[] { "PGRP_Alpha_v0.5.3", "PGRP_Alpha_v0.5.2", "PGRP_Alpha_v0.5.1", "PGRP_Alpha_v0.4.2" })
        {
            var exe = Path.Combine(root, version, "GTA_San_Andreas", "gta_sa.exe");
            if (!IsGameReady(exe)) continue;
            _config.GtaExecutable = exe;
            SaveSettings();
            return;
        }
    }

    private static bool IsGameReady(string path)
    {
        if (string.IsNullOrWhiteSpace(path) || !File.Exists(path)
            || !Path.GetFileName(path).Equals("gta_sa.exe", StringComparison.OrdinalIgnoreCase))
            return false;
        var dir = Path.GetDirectoryName(path);
        return dir != null && File.Exists(Path.Combine(dir, "opensamp.exe")) &&
            File.Exists(Path.Combine(dir, "Client.Native.dll")) &&
            Directory.Exists(Path.Combine(dir, "models")) &&
            Directory.Exists(Path.Combine(dir, "data"));
    }

    private void BrowseGame()
    {
        using var dlg = new OpenFileDialog
        {
            Title = "Select installed PGRP gta_sa.exe",
            Filter = "GTA San Andreas (gta_sa.exe)|gta_sa.exe",
            CheckFileExists = true
        };
        if (dlg.ShowDialog(this) != DialogResult.OK) return;
        if (!IsGameReady(dlg.FileName))
        {
            MessageBox.Show(this,
                "این مسیر باید پوشه نسخه نصب‌شده PGRP باشد و opensamp.exe و Client.Native.dll را داشته باشد.",
                "فایل‌های کلاینت پیدا نشد", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }
        _config.GtaExecutable = dlg.FileName;
        _gamePath.Text = dlg.FileName;
        SaveSettings();
        UpdateClientLabel();
    }

    private void UpdateClientLabel()
    {
        if (!IsGameReady(_config.GtaExecutable))
        {
            _client.Text = "نسخه بازی شناسایی نشد. مسیر GTA نسخه نصب‌شده PGRP را در تنظیمات مشخص کنید.";
            return;
        }
        var root = Directory.GetParent(Path.GetDirectoryName(_config.GtaExecutable)!)?.FullName;
        var manifest = root == null ? "" : Path.Combine(root, "PGRP_Installed_Version.txt");
        var version = "OpenSAMP PGRP (version manifest unavailable)";
        try
        {
            if (File.Exists(manifest)) version = File.ReadLines(manifest).FirstOrDefault() ?? version;
        }
        catch { }
        _client.Text = version;
    }

    private void LaunchGame()
    {
        var nickname = _config.Nickname.Trim();
        if (!Regex.IsMatch(nickname, "^[A-Za-z0-9]+_[A-Za-z0-9_]+$") ||
            nickname.Length < 3 || nickname.Length > 24)
        {
            ShowPage("settings");
            MessageBox.Show(this, "نام شخصیت باید به شکل Name_Surname و بین ۳ تا ۲۴ کاراکتر باشد.",
                "نام شخصیت معتبر نیست", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }
        if (!IsGameReady(_config.GtaExecutable))
        {
            ShowPage("settings");
            MessageBox.Show(this, "ابتدا مسیر فایل gta_sa.exe در نسخه نصب‌شده PGRP را انتخاب کنید.",
                "کلاینت آماده نیست", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }

        try
        {
            string dir = Path.GetDirectoryName(_config.GtaExecutable)!;
            var psi = new ProcessStartInfo(Path.Combine(dir, "opensamp.exe"))
            {
                WorkingDirectory = dir,
                UseShellExecute = false
            };
            // Read by the optional PGRP v0.5.2 native patch. Existing clients
            // still launch, but require manual //connect as in v0.5.1.
            psi.Environment["PGRP_AUTOCONNECT_NICK"] = nickname;
            var started = Process.Start(psi);
            if (started == null) throw new InvalidOperationException("Launcher process was not created.");
            // Hand off to the game process; release memory on low-spec PCs.
            Close();
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, ex.Message, "اجرای بازی ناموفق بود",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    private async Task CheckServerAsync()
    {
        if (_checking || IsDisposed) return;
        _checking = true;
        try
        {
            // Standard SA-MP/open.mp UDP 'i' query, not a gameplay connection.
            var ip = IPAddress.Parse(Host).GetAddressBytes();
            var request = new byte[11];
            request[0] = (byte)'S'; request[1] = (byte)'A';
            request[2] = (byte)'M'; request[3] = (byte)'P';
            Array.Copy(ip, 0, request, 4, 4);
            BinaryPrimitives.WriteUInt16LittleEndian(request.AsSpan(8), Port);
            request[10] = (byte)'i';
            using var udp = new UdpClient(AddressFamily.InterNetwork);
            var sw = Stopwatch.StartNew();
            await udp.SendAsync(request, request.Length, new IPEndPoint(IPAddress.Parse(Host), Port));
            var response = udp.ReceiveAsync();
            if (await Task.WhenAny(response, Task.Delay(1800)) != response)
                throw new TimeoutException("UDP query timed out");
            var bytes = (await response).Buffer;
            sw.Stop();
            if (bytes.Length < 16 || bytes[0] != 'S' || bytes[1] != 'A' ||
                bytes[2] != 'M' || bytes[3] != 'P' || bytes[10] != (byte)'i')
                throw new InvalidDataException("Unexpected server query response");
            ushort players = BinaryPrimitives.ReadUInt16LittleEndian(bytes.AsSpan(12, 2));
            ushort maxPlayers = BinaryPrimitives.ReadUInt16LittleEndian(bytes.AsSpan(14, 2));
            _status.Text = "آنلاین";
            _players.Text = $"{players} / {maxPlayers}";
            _ping.Text = $"{sw.ElapsedMilliseconds} ms";
        }
        catch
        {
            _status.Text = "پاسخ نداد";
            _players.Text = "— / —";
            _ping.Text = "— ms";
        }
        finally { _checking = false; }
    }
}
