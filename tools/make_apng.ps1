# Makes a light animated PNG of the "tablo" board for web pages from the designer's GIF:
#   docs/fastrevers-tablo.gif (512 px, ~2 MB)  ->  docs/fastrevers-tablo-256.png (APNG, 256 px, ~0.5 MB)
# Keeps transparency and the GIF's timing; each frame stores only the part that changed. All browsers show APNG.
#   powershell -File tools/make_apng.ps1 [-Size 256]
param([int]$Size = 256)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Add-Type -ReferencedAssemblies System.Drawing @"
using System; using System.IO; using System.Drawing; using System.Drawing.Imaging; using System.Collections.Generic;
public static class Apng {
  static uint[] crcT;
  static uint Crc(byte[] d) {
    if (crcT == null) { crcT = new uint[256]; for (uint i = 0; i < 256; i++) { uint x = i; for (int k = 0; k < 8; k++) x = (x & 1) != 0 ? 0xEDB88320 ^ (x >> 1) : x >> 1; crcT[i] = x; } }
    uint c = 0xFFFFFFFF; foreach (var b in d) c = crcT[(c ^ b) & 0xFF] ^ (c >> 8); return c ^ 0xFFFFFFFF;
  }
  static void BE(Stream s, uint v) { s.WriteByte((byte)(v >> 24)); s.WriteByte((byte)(v >> 16)); s.WriteByte((byte)(v >> 8)); s.WriteByte((byte)v); }
  static void Chunk(Stream s, string type, byte[] data) {
    BE(s, (uint)data.Length); var all = new byte[4 + data.Length];
    System.Text.Encoding.ASCII.GetBytes(type).CopyTo(all, 0); data.CopyTo(all, 4);
    s.Write(all, 0, all.Length); BE(s, Crc(all));
  }
  static List<byte[]> Idats(Bitmap b) {   // the compressed pixel data GDI+ writes for one frame
    var ms = new MemoryStream(); b.Save(ms, ImageFormat.Png); var p = ms.ToArray(); var l = new List<byte[]>(); int o = 8;
    while (o < p.Length) { int len = p[o] << 24 | p[o + 1] << 16 | p[o + 2] << 8 | p[o + 3];
      if (System.Text.Encoding.ASCII.GetString(p, o + 4, 4) == "IDAT") { var d = new byte[len]; Buffer.BlockCopy(p, o + 8, d, 0, len); l.Add(d); }
      o += 12 + len; }
    return l;
  }
  static Rectangle Diff(Bitmap a, Bitmap b) {
    int x0 = a.Width, y0 = a.Height, x1 = -1, y1 = -1;
    for (int y = 0; y < a.Height; y++) for (int x = 0; x < a.Width; x++)
      if (a.GetPixel(x, y) != b.GetPixel(x, y)) { if (x < x0) x0 = x; if (y < y0) y0 = y; if (x > x1) x1 = x; if (y > y1) y1 = y; }
    return x1 < 0 ? Rectangle.Empty : new Rectangle(x0, y0, x1 - x0 + 1, y1 - y0 + 1);
  }
  public static string Make(string gif, string outp, int size) {
    var g = Image.FromFile(gif); var fd = new FrameDimension(g.FrameDimensionsList[0]); int n = g.GetFrameCount(fd);
    var delays = g.GetPropertyItem(0x5100).Value; var frames = new List<Bitmap>(); var dl = new List<int>();
    for (int i = 0; i < n; i++) {
      g.SelectActiveFrame(fd, i); var b = new Bitmap(size, size, PixelFormat.Format32bppArgb);
      using (var gr = Graphics.FromImage(b)) { gr.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
        gr.PixelOffsetMode = System.Drawing.Drawing2D.PixelOffsetMode.HighQuality; gr.DrawImage(g, 0, 0, size, size); }
      int d = BitConverter.ToInt32(delays, 4 * i) * 10;
      if (frames.Count > 0 && Diff(frames[frames.Count - 1], b).IsEmpty) { dl[dl.Count - 1] += d; b.Dispose(); continue; }
      frames.Add(b); dl.Add(d);
    }
    using (var s = new FileStream(outp, FileMode.Create)) {
      s.Write(new byte[] { 137, 80, 78, 71, 13, 10, 26, 10 }, 0, 8);
      Chunk(s, "IHDR", new byte[] { 0, 0, (byte)(size >> 8), (byte)size, 0, 0, (byte)(size >> 8), (byte)size, 8, 6, 0, 0, 0 });
      var ac = new MemoryStream(); BE(ac, (uint)frames.Count); BE(ac, 0); Chunk(s, "acTL", ac.ToArray());   // 0 = loop forever
      uint seq = 0;
      for (int i = 0; i < frames.Count; i++) {
        Rectangle r = i == 0 ? new Rectangle(0, 0, size, size) : Diff(frames[i - 1], frames[i]);
        var fc = new MemoryStream(); BE(fc, seq++); BE(fc, (uint)r.Width); BE(fc, (uint)r.Height); BE(fc, (uint)r.X); BE(fc, (uint)r.Y);
        fc.WriteByte((byte)(dl[i] >> 8)); fc.WriteByte((byte)dl[i]); fc.WriteByte(1000 >> 8); fc.WriteByte(1000 & 255);   // delay in ms
        fc.WriteByte(0); fc.WriteByte(0); Chunk(s, "fcTL", fc.ToArray());                                                     // keep, replace region
        using (var crop = frames[i].Clone(r, PixelFormat.Format32bppArgb))
          foreach (var d in Idats(crop)) {
            if (i == 0) Chunk(s, "IDAT", d);
            else { var f = new MemoryStream(); BE(f, seq++); f.Write(d, 0, d.Length); Chunk(s, "fdAT", f.ToArray()); }
          }
      }
      Chunk(s, "IEND", new byte[0]);
      return frames.Count + " frames, " + s.Length + " bytes";
    }
  }
}
"@
$out = Join-Path $root "docs\fastrevers-tablo-$Size.png"
"$out : " + [Apng]::Make((Join-Path $root 'docs\fastrevers-tablo.gif'), $out, $Size)
