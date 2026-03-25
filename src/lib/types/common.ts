// Pagination
export interface PaginatedResult<T> {
  data: T[]
  count: number
  page: number
  pageSize: number
  totalPages: number
}

export interface PaginationParams {
  page?: number
  pageSize?: number
  search?: string
  sortBy?: string
  sortDir?: 'asc' | 'desc'
}

// API Response
export interface ApiError {
  message: string
  code?: string
  details?: string
}

// Select option
export interface SelectOption {
  value: string
  label: string
  disabled?: boolean
}
