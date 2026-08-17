from pathlib import Path

root = Path(__file__).resolve().parents[1]
path = root / 'src/features/ai-operations/hooks.ts'
text = path.read_text(encoding='utf-8')
old = '      await invalidateAiOperationsQueries(queryClient)'
new = '      await queryClient.invalidateQueries({ queryKey: aiOperationsKeys.all })'
if old not in text:
    raise RuntimeError('expected AI Operations hook invalidation anchor missing')
path.write_text(text.replace(old, new, 1), encoding='utf-8')
Path(__file__).unlink(missing_ok=True)
