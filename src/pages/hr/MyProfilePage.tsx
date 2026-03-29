import { useNavigate } from 'react-router-dom'
import {
  User, Building2, Briefcase, Calendar, CreditCard,
  Clock, ArrowLeft, FileText, Wallet, Shield,
  CalendarOff,
} from 'lucide-react'
import { useCurrentEmployee, useHRLeaveBalances } from '@/hooks/useQueryHooks'
import { useAuthStore } from '@/stores/auth-store'
import PageHeader from '@/components/shared/PageHeader'
import Spinner from '@/components/ui/Spinner'
import Badge from '@/components/ui/Badge'

const fmtDate = (d?: string | null) =>
  d ? new Date(d).toLocaleDateString('ar-EG-u-nu-latn', { day: 'numeric', month: 'long', year: 'numeric' }) : '—'

const fmtCurrency = (n: number) =>
  n.toLocaleString('ar-EG-u-nu-latn', { minimumFractionDigits: 2, maximumFractionDigits: 2 }) + ' ج.م'

// ─── بطاقة معلومة ────────────────────────────────
function InfoCard({ label, value, icon, muted = false }: {
  label: string; value: React.ReactNode;
  icon: React.ReactNode; muted?: boolean;
}) {
  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 'var(--space-3)',
      padding: 'var(--space-3)',
      background: 'var(--bg-surface-2)',
      borderRadius: 'var(--radius-md)',
      border: '1px solid var(--border-color)',
    }}>
      <div style={{
        width: 36, height: 36, borderRadius: 'var(--radius-md)',
        background: 'color-mix(in srgb, var(--color-primary) 10%, transparent)',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        color: 'var(--color-primary)', flexShrink: 0,
      }}>
        {icon}
      </div>
      <div>
        <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>{label}</div>
        <div style={{
          fontSize: 'var(--text-sm)', fontWeight: 600,
          color: muted ? 'var(--text-muted)' : 'var(--text-primary)',
        }}>{value}</div>
      </div>
    </div>
  )
}

// ─── بطاقة رصيد إجازة ───────────────────────────
function LeaveBalanceCard({ label, used, remaining, total, icon }: {
  label: string; used: number; remaining: number; total: number; icon: React.ReactNode;
}) {
  const pct = total > 0 ? Math.min(100, (used / total) * 100) : 0
  const color = remaining === 0 ? 'var(--color-danger)' : remaining <= 3 ? 'var(--color-warning)' : 'var(--color-success)'
  return (
    <div style={{
      padding: 'var(--space-4)',
      background: 'var(--bg-surface-2)',
      borderRadius: 'var(--radius-lg)',
      border: '1px solid var(--border-color)',
    }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 'var(--space-2)' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-2)', fontSize: 'var(--text-sm)', fontWeight: 600 }}>
          {icon} {label}
        </div>
        <span style={{ fontSize: 'var(--text-xs)', color, fontWeight: 700 }}>
          {remaining} / {total} يوم
        </span>
      </div>
      <div style={{ height: 6, background: 'var(--bg-surface-3, var(--border-color))', borderRadius: 99, overflow: 'hidden' }}>
        <div style={{
          height: '100%', width: `${pct}%`, borderRadius: 99,
          background: pct > 80 ? 'var(--color-danger)' : pct > 50 ? 'var(--color-warning)' : 'var(--color-success)',
          transition: 'width 0.5s ease',
        }} />
      </div>
      <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', marginTop: 4 }}>
        مُستخدم: {used} يوم
      </div>
    </div>
  )
}

// ─── رابط سريع ───────────────────────────────────
function QuickLink({ label, icon, path, color }: {
  label: string; icon: React.ReactNode; path: string; color: string;
}) {
  const navigate = useNavigate()
  return (
    <button
      onClick={() => navigate(path)}
      style={{
        display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 'var(--space-2)',
        padding: 'var(--space-4)',
        background: 'var(--bg-surface-2)',
        border: '1px solid var(--border-color)',
        borderRadius: 'var(--radius-lg)',
        cursor: 'pointer', fontFamily: 'var(--font-sans)',
        transition: 'all 0.15s',
        flex: 1, minWidth: 80,
      }}
      onMouseEnter={e => (e.currentTarget.style.borderColor = color)}
      onMouseLeave={e => (e.currentTarget.style.borderColor = 'var(--border-color)')}
    >
      <div style={{
        width: 40, height: 40, borderRadius: 'var(--radius-md)',
        background: `color-mix(in srgb, ${color} 12%, transparent)`,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        color,
      }}>{icon}</div>
      <span style={{ fontSize: 'var(--text-xs)', fontWeight: 600, color: 'var(--text-primary)' }}>{label}</span>
    </button>
  )
}

// ════════════════════════════════════════════════════
// Main Page
// ════════════════════════════════════════════════════
export default function MyProfilePage() {
  const { data: employee, isLoading } = useCurrentEmployee()
  const profile = useAuthStore(s => s.profile)

  // جلب رصيد الإجازات
  const { data: balances = [] } = useHRLeaveBalances(
    employee?.id ?? null,
    new Date().getFullYear()
  )

  if (isLoading) return (
    <div style={{ minHeight: '60vh', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
      <Spinner />
    </div>
  )

  if (!employee) return (
    <div className="page-container animate-enter">
      <PageHeader
        title="ملفي الشخصي"
        breadcrumbs={[{ label: 'الموارد البشرية', path: '/hr' }, { label: 'ملفي' }]}
      />
      <div className="edara-card" style={{ textAlign: 'center', padding: 'var(--space-12)' }}>
        <User size={48} style={{ color: 'var(--text-muted)', opacity: 0.4, margin: '0 auto var(--space-4)' }} />
        <div style={{ fontWeight: 700, fontSize: 'var(--text-lg)', marginBottom: 'var(--space-2)' }}>
          غير مرتبط بسجل موظف
        </div>
        <div style={{ fontSize: 'var(--text-sm)', color: 'var(--text-muted)', maxWidth: 360, margin: '0 auto' }}>
          حسابك ({profile?.email}) غير مرتبط بأي سجل في نظام الموارد البشرية.
          تواصل مع مدير HR لربط حسابك.
        </div>
      </div>
    </div>
  )



  return (
    <div className="page-container animate-enter">
      <PageHeader
        title="ملفي الشخصي"
        subtitle="بياناتي وإجازاتي ورواتبي"
        breadcrumbs={[
          { label: 'الموارد البشرية', path: '/hr' },
          { label: 'ملفي' },
        ]}
      />

      {/* ── بطاقة الهوية ── */}
      <div className="edara-card" style={{ marginBottom: 'var(--space-4)' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-4)', marginBottom: 'var(--space-5)' }}>
          <div style={{
            width: 64, height: 64, borderRadius: 'var(--radius-full)',
            background: 'color-mix(in srgb, var(--color-primary) 12%, transparent)',
            border: '2px solid color-mix(in srgb, var(--color-primary) 30%, transparent)',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            fontSize: '1.8rem', fontWeight: 800, color: 'var(--color-primary)', flexShrink: 0,
          }}>
            {employee.full_name.charAt(0)}
          </div>
          <div>
            <div style={{ fontWeight: 800, fontSize: 'var(--text-xl)', color: 'var(--text-primary)' }}>
              {employee.full_name}
            </div>
            <div style={{ fontSize: 'var(--text-sm)', color: 'var(--text-muted)' }}>
              {employee.position?.name ?? 'بدون مسمى وظيفي'} {employee.department?.name ? `— ${employee.department.name}` : ''}
            </div>
            <div style={{ display: 'flex', gap: 'var(--space-2)', marginTop: 'var(--space-1)' }}>
              <Badge variant={employee.status === 'active' ? 'success' : 'warning'}>
                {employee.status === 'active' ? 'نشط' : employee.status === 'on_leave' ? 'في إجازة' : 'موقوف'}
              </Badge>
              <span style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', display: 'flex', alignItems: 'center' }}>
                #{employee.employee_number}
              </span>
            </div>
          </div>
        </div>

        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(200px, 1fr))', gap: 'var(--space-3)' }}>
          <InfoCard label="القسم"           value={employee.department?.name ?? 'غير محدد'} icon={<Building2 size={16} />} />
          <InfoCard label="المسمى الوظيفي"  value={employee.position?.name  ?? 'غير محدد'} icon={<Briefcase  size={16} />} />
          <InfoCard label="تاريخ التعيين"   value={fmtDate(employee.hire_date)}             icon={<Calendar   size={16} />} />
          <InfoCard label="الراتب الأساسي"  value={fmtCurrency(employee.base_salary ?? 0)} icon={<CreditCard size={16} />} />
          {employee.personal_phone && (
            <InfoCard label="الهاتف" value={employee.personal_phone} icon={<User size={16} />} muted />
          )}        
          {employee.national_id && (
            <InfoCard label="الرقم القومي" value={employee.national_id} icon={<Shield size={16} />} muted />
          )}
        </div>
      </div>

      {/* ── رصيد الإجازات ── */}
      <div className="edara-card" style={{ marginBottom: 'var(--space-4)' }}>
        <div style={{ fontWeight: 700, fontSize: 'var(--text-base)', marginBottom: 'var(--space-4)', display: 'flex', alignItems: 'center', gap: 'var(--space-2)' }}>
          <CalendarOff size={16} /> رصيد الإجازات — {new Date().getFullYear()}
        </div>
        {balances.length === 0 ? (
          <div style={{ textAlign: 'center', color: 'var(--text-muted)', fontSize: 'var(--text-sm)', padding: 'var(--space-6)' }}>
            لا توجد بيانات رصيد إجازات لهذا العام
          </div>
        ) : (
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(220px, 1fr))', gap: 'var(--space-3)' }}>
            {balances.map(b => (
              <LeaveBalanceCard
                key={b.id}
                label={b.leave_type?.name ?? 'إجازة'}
                used={b.used_days ?? 0}
                remaining={b.remaining_days ?? 0}
                total={b.total_days ?? 0}
                icon={<Calendar size={14} />}
              />
            ))}
          </div>
        )}
      </div>


      {/* ── الروابط السريعة ── */}
      <div className="edara-card">
        <div style={{ fontWeight: 700, fontSize: 'var(--text-base)', marginBottom: 'var(--space-4)', display: 'flex', alignItems: 'center', gap: 'var(--space-2)' }}>
          <ArrowLeft size={16} /> إجراءات سريعة
        </div>
        <div style={{ display: 'flex', gap: 'var(--space-3)', flexWrap: 'wrap' }}>
          <QuickLink label="طلب إجازة"   icon={<CalendarOff size={20} />} path="/hr/leaves"       color="var(--color-success)" />
          <QuickLink label="طلب سلفة"    icon={<Wallet      size={20} />} path="/hr/advances"     color="var(--color-warning)" />
          <QuickLink label="طلب إذن"     icon={<Clock       size={20} />} path="/hr/permissions"  color="var(--color-info)"    />
          <QuickLink label="الحضور"      icon={<FileText    size={20} />} path="/hr/attendance"   color="var(--color-primary)" />
        </div>
      </div>
    </div>
  )
}
