import './VisitGuidance.css'

interface VisitGuidanceProps {
  title: string
  text: string | null | undefined
  id?: string
}

/** Read-only instructions already returned with a visit plan or item. */
export default function VisitGuidance({ title, text, id }: VisitGuidanceProps) {
  if (!text?.trim()) return null

  return (
    <section id={id} className="visit-guidance" aria-label={title}>
      <h3 className="visit-guidance-title">{title}</h3>
      <p className="visit-guidance-text" dir="auto">{text}</p>
    </section>
  )
}
