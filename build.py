# Construit dist/index-oryxo.html : minifie src/main.js et l'insère dans src/shell.html (à la place de /*__MAIN__*/)
# Besoin : Node.js + esbuild  (npm i -D esbuild   ou   npx esbuild)
import subprocess, sys, gzip, os, shutil
root = os.path.dirname(os.path.abspath(__file__))
esb = shutil.which('esbuild') or os.path.join(root, 'node_modules', '.bin', 'esbuild')
cmd = [esb] if os.path.exists(esb) else ['npx', '--yes', 'esbuild']
r = subprocess.run(cmd + [os.path.join(root, 'src', 'main.js'), '--minify', '--target=es2020', '--legal-comments=none', '--log-level=error'], capture_output=True, text=True)
if r.returncode: sys.exit(r.stderr[:3000])
shell = open(os.path.join(root, 'src', 'shell.html'), encoding='utf-8').read()
out = shell.replace('/*__MAIN__*/', r.stdout.strip().replace('</script', '<\\/script'), 1)
os.makedirs(os.path.join(root, 'dist'), exist_ok=True)
open(os.path.join(root, 'dist', 'index-oryxo.html'), 'w', encoding='utf-8').write(out)
print('ok', len(out.encode()) // 1024, 'Ko, gzip', len(gzip.compress(out.encode(), 9)) // 1024, 'Ko')
