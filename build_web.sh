#!/usr/bin/env bash
# ============================================================
# build_web.sh — Study Grades Voice Web Build Script
# المطور: م. باسل أشرف
# الإصدار: 2.0.0
#
# يقوم بـ:
#   1. بناء Flutter Web بـ release mode
#   2. حقن useLocalCanvasKit:true لتجنب CDN gstatic.com
#   3. تشغيل خادم CORS محلي على المنفذ 5060
# ============================================================

set -e
cd "$(dirname "$0")"

echo "🔨 [1/3] Building Flutter Web (release)..."
flutter build web --release

echo "🔧 [2/3] Patching flutter_bootstrap.js (useLocalCanvasKit=true)..."
python3 - << 'PYEOF'
import sys, re

path = "build/web/flutter_bootstrap.js"
content = open(path).read()

# استبدال: أضف useLocalCanvasKit:true في كائن buildConfig
# يبحث عن النمط الدقيق الذي يُنتجه Flutter
old = (
    '{"engineRevision":'
    '"c29809135135e262a912cf583b2c90deb9ded610",'
    '"builds":[{"compileTarget":"dart2js","renderer":"canvaskit",'
    '"mainJsPath":"main.dart.js"},{}]}'
)
new = (
    '{"engineRevision":'
    '"c29809135135e262a912cf583b2c90deb9ded610",'
    '"useLocalCanvasKit":true,'
    '"builds":[{"compileTarget":"dart2js","renderer":"canvaskit",'
    '"mainJsPath":"main.dart.js"},{}]}'
)

if old in content:
    content = content.replace(old, new)
    open(path, "w").write(content)
    print("  ✅ useLocalCanvasKit:true injected — CanvasKit يُحمَّل محلياً")
else:
    # بحث بديل عبر regex لأي نسخة Flutter مستقبلية
    pattern = r'(_flutter\.buildConfig\s*=\s*\{)("engineRevision")'
    replacement = r'\1"useLocalCanvasKit":true,\2'
    new_content = re.sub(pattern, replacement, content)
    if new_content != content:
        open(path, "w").write(new_content)
        print("  ✅ useLocalCanvasKit:true injected via regex fallback")
    else:
        print("  ⚠️  لم يُعثر على النمط — تحقق يدوياً من flutter_bootstrap.js")
        sys.exit(1)
PYEOF

echo "🚀 [3/3] Starting CORS server on port 5060..."
# إيقاف أي خادم سابق
lsof -ti:5060 | xargs -r kill -9 2>/dev/null || true
sleep 1

cd build/web
python3 -c "
import http.server, socketserver

class CORSHandler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('X-Frame-Options', 'ALLOWALL')
        self.send_header('Content-Security-Policy', 'frame-ancestors *')
        super().end_headers()
    def log_message(self, fmt, *args):
        pass  # هادئ — بدون سجلات غير ضرورية

socketserver.TCPServer.allow_reuse_address = True
print('✅ Server running: http://localhost:5060')
with socketserver.TCPServer(('0.0.0.0', 5060), CORSHandler) as httpd:
    httpd.serve_forever()
"
