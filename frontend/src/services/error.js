export function toErrorMessage(error) {
  if (error.response) {
    const { data, status } = error.response
    if (data && Array.isArray(data.errors) && data.errors.length > 0) {
      const first = data.errors[0]
      if (first && first.detail) return first.detail
      if (first && first.title) return first.title
    }
    if (status === 404) return 'Recurso no encontrado'
    if (status === 400) return 'Solicitud inválida'
    if (status === 422) return 'No se pudo procesar la solicitud'
    if (status >= 500) return 'Error interno del servidor'
    return `Error HTTP ${status}`
  }
  if (error.request) return 'No se pudo conectar con el servidor'
  return error.message || 'Error desconocido'
}