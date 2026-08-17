from pathlib import Path
root = Path(__file__).resolve().parents[1]
p = root / 'src/pages/work/management/AiOperationsManagementPanel.tsx'
text = p.read_text(encoding='utf-8')
old = '<li>CREATE_WORK فقط هي المدعومة تنفيذيًا في Credit slice الحالية.</li>'
new = '<li>CREATE_WORK وESCALATE لا يُنفذان إلا بعد اعتماد بشري صريح وخطوة تنفيذ مستقلة.</li>'
if old not in text:
    raise RuntimeError('stale AI Operations safety copy anchor missing')
p.write_text(text.replace(old, new, 1), encoding='utf-8')
Path(__file__).unlink(missing_ok=True)
(root / '.github/workflows/fix-aiops-safety-copy.yml').unlink(missing_ok=True)
