# Construit dist/test.html : version NON minifiée + accroche window.__g pour piloter le jeu dans des tests (Playwright)
# window.__g.p (joueur), .Se (balles), .N (tanks), .f (réseau), .q (compte), .ev("code") évalue dans le scope du jeu
import subprocess, sys, os, shutil
root = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
src = open(os.path.join(root, 'src', 'main.js'), encoding='utf-8').read()
hook = "window.__g={get p(){return p},get Se(){return Se},get N(){return N},get f(){return f},get q(){return q},setG:(v)=>{G=v},ev:(s)=>eval(s)};\n"
src = src.replace("  function Fl(e, t, n) {", "  " + hook + "  function Fl(e, t, n) {", 1)
esb = shutil.which('esbuild')
cmd = [esb] if esb else ['npx', '--yes', 'esbuild']
r = subprocess.run(cmd + ['--loader=js', '--target=es2020', '--log-level=error'], input=src, capture_output=True, text=True)
if r.returncode: sys.exit(r.stderr)
out = open(os.path.join(root, 'src', 'shell.html'), encoding='utf-8').read().replace('/*__MAIN__*/', r.stdout.replace('</script', '<\\/script'), 1)
dst = sys.argv[1] if len(sys.argv) > 1 else os.path.join(root, 'dist', 'test.html')
open(dst, 'w', encoding='utf-8').write(out); print('test built ->', dst)
