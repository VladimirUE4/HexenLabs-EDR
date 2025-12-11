import { createContext, useContext, useState, useEffect, useCallback, ReactNode } from 'react'
import axios from 'axios'

interface AuthContextType {
  token: string | null
  refreshToken: string | null
  login: (username: string, password: string) => Promise<void>
  logout: () => void
  isAuthenticated: boolean
  loading: boolean
}

const AuthContext = createContext<AuthContextType | undefined>(undefined)

export function AuthProvider({ children }: { children: ReactNode }) {
  const [token, setToken] = useState<string | null>(localStorage.getItem('token'))
  const [refreshToken, setRefreshToken] = useState<string | null>(localStorage.getItem('refreshToken'))
  const [loading, setLoading] = useState(true)

  const logout = useCallback(() => {
    setToken(null)
    setRefreshToken(null)
    localStorage.removeItem('token')
    localStorage.removeItem('refreshToken')
    delete axios.defaults.headers.common['Authorization']
  }, [])

  const login = useCallback(async (username: string, password: string) => {
    const response = await axios.post('/api/auth/login', { username, password })
    const { token: newToken, refresh_token } = response.data
    setToken(newToken)
    setRefreshToken(refresh_token)
    localStorage.setItem('token', newToken)
    localStorage.setItem('refreshToken', refresh_token)
    axios.defaults.headers.common['Authorization'] = `Bearer ${newToken}`
  }, [])

  useEffect(() => {
    // Set up axios interceptor for token refresh
    const interceptor = axios.interceptors.response.use(
      (response) => response,
      async (error) => {
        if (error.response?.status === 401 && refreshToken) {
          try {
            const response = await axios.post('/api/auth/refresh', {
              refresh_token: refreshToken,
            })
            const newToken = response.data.token
            setToken(newToken)
            localStorage.setItem('token', newToken)
            axios.defaults.headers.common['Authorization'] = `Bearer ${newToken}`
            return axios.request(error.config)
          } catch (refreshError) {
            logout()
            return Promise.reject(refreshError)
          }
        }
        return Promise.reject(error)
      }
    )

    // Set default auth header
    if (token) {
      axios.defaults.headers.common['Authorization'] = `Bearer ${token}`
    }

    setLoading(false)

    return () => {
      axios.interceptors.response.eject(interceptor)
    }
  }, [token, refreshToken, logout])

  return (
    <AuthContext.Provider
      value={{
        token,
        refreshToken,
        login,
        logout,
        isAuthenticated: !!token,
        loading,
      }}
    >
      {children}
    </AuthContext.Provider>
  )
}

export function useAuth() {
  const context = useContext(AuthContext)
  if (context === undefined) {
    throw new Error('useAuth must be used within an AuthProvider')
  }
  return context
}

