export default function SkeletonCard({ height = 140 }: { height?: number }) {
  return (
    <div
      style={{
        height: `${height}px`,
        borderRadius: 'var(--radius-lg)',
        background: 'linear-gradient(90deg, var(--bg-surface-2) 25%, var(--bg-hover) 50%, var(--bg-surface-2) 75%)',
        backgroundSize: '200% 100%',
        animation: 'shimmer 1.5s infinite',
        border: '1px solid var(--border-primary)',
      }}
    />
  )
}
