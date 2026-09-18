import { forwardRef } from 'react'
import Input, { type InputProps } from './Input'

export type DateFieldProps = Omit<InputProps, 'type'>

/**
 * DateField — domain-agnostic native date input composed through V2 Field/Input.
 *
 * Owns date-control presentation and accessible Field plumbing only. Parsing,
 * normalization, range ordering and business meaning remain caller-owned.
 */
const DateField = forwardRef<HTMLInputElement, DateFieldProps>((props, ref) => (
  <Input {...props} ref={ref} type="date" />
))

DateField.displayName = 'DateField'
export default DateField
