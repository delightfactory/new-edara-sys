import type { CSSProperties } from 'react'
import { Building, Edit, History, MapPin, Plus, Trash2, Users } from 'lucide-react'
import type { CustomerBranch, CustomerContact, CustomerCreditHistory } from '@/lib/types/master-data'
import Card from '@/components/patterns/Card'
import KeyValueList from '@/components/patterns/KeyValueList'
import SectionHeader from '@/components/patterns/SectionHeader'
import StatePanel from '@/components/patterns/StatePanel'
import StatusBadge from '@/components/patterns/StatusBadge'

const collectionGridStyle: CSSProperties = {
  display: 'grid',
  gridTemplateColumns: 'repeat(auto-fit, minmax(min(100%, 18rem), 1fr))',
  gap: 'var(--space-3)',
}

const cardActionsStyle: CSSProperties = {
  display: 'flex',
  alignItems: 'center',
  gap: 'var(--space-1)',
  flexWrap: 'wrap',
  marginTop: 'var(--space-3)',
}

const creditTableScrollerStyle: CSSProperties = {
  overflowX: 'auto',
  WebkitOverflowScrolling: 'touch',
}

export interface CustomerBranchesPanelProps {
  branches: CustomerBranch[]
  canUpdate: boolean
  onAdd: () => void
  onEdit: (branch: CustomerBranch) => void
  onDelete: (id: string, label: string) => void
}

export function CustomerBranchesPanel({
  branches,
  canUpdate,
  onAdd,
  onEdit,
  onDelete,
}: CustomerBranchesPanelProps) {
  return (
    <Card padding="lg">
      <SectionHeader
        title="فروع العميل"
        icon={<Building size={18} />}
        action={canUpdate ? (
          <button type="button" className="btn btn-primary btn-sm btn-touch" onClick={onAdd}>
            <Plus size={14} /> إضافة فرع
          </button>
        ) : undefined}
      />

      <div style={{ marginTop: 'var(--space-4)' }}>
        {branches.length === 0 ? (
          <StatePanel
            kind="empty"
            icon={<Building size={38} />}
            title="لا يوجد فروع لهذا العميل"
            description="أضف فرعاً لتسجيل مواقع التسليم."
            action={canUpdate ? (
              <button type="button" className="btn btn-secondary btn-sm btn-touch" onClick={onAdd}>
                <Plus size={14} /> إضافة أول فرع
              </button>
            ) : undefined}
            compact
          />
        ) : (
          <div style={collectionGridStyle}>
            {branches.map(branch => (
              <Card key={branch.id} padding="md" surface={branch.is_primary ? 'elevated' : 'default'}>
                <SectionHeader
                  headingLevel={3}
                  title={branch.name}
                  action={branch.is_primary ? <StatusBadge label="أساسي" tone="info" /> : undefined}
                />

                <div style={{ marginTop: 'var(--space-3)' }}>
                  <KeyValueList
                    columns={1}
                    compact
                    items={[
                      ...(branch.address ? [{ key: 'address', label: 'العنوان', value: branch.address }] : []),
                      ...(branch.phone ? [{ key: 'phone', label: 'الهاتف', value: <span dir="ltr">{branch.phone}</span> }] : []),
                      ...(branch.contact_name ? [{ key: 'contact', label: 'مسؤول التواصل', value: branch.contact_name }] : []),
                      ...(branch.latitude && branch.longitude ? [{
                        key: 'location',
                        label: 'الموقع',
                        value: (
                          <span dir="ltr">
                            <MapPin size={12} aria-hidden="true" style={{ display: 'inline', marginInlineEnd: 4 }} />
                            {Number(branch.latitude).toFixed(5)}, {Number(branch.longitude).toFixed(5)}
                          </span>
                        ),
                      }] : []),
                    ]}
                  />
                </div>

                {canUpdate && (
                  <div style={cardActionsStyle}>
                    <button type="button" className="btn btn-ghost btn-sm btn-touch" onClick={() => onEdit(branch)}>
                      <Edit size={14} /> تعديل
                    </button>
                    <button
                      type="button"
                      className="btn btn-danger btn-sm btn-icon btn-touch"
                      aria-label={`حذف فرع ${branch.name}`}
                      onClick={() => onDelete(branch.id, branch.name)}
                    >
                      <Trash2 size={14} />
                    </button>
                  </div>
                )}
              </Card>
            ))}
          </div>
        )}
      </div>
    </Card>
  )
}

export interface CustomerContactsPanelProps {
  contacts: CustomerContact[]
  canUpdate: boolean
  onAdd: () => void
  onEdit: (contact: CustomerContact) => void
  onDelete: (id: string, label: string) => void
}

export function CustomerContactsPanel({
  contacts,
  canUpdate,
  onAdd,
  onEdit,
  onDelete,
}: CustomerContactsPanelProps) {
  return (
    <Card padding="lg">
      <SectionHeader
        title="جهات الاتصال"
        icon={<Users size={18} />}
        action={canUpdate ? (
          <button type="button" className="btn btn-primary btn-sm btn-touch" onClick={onAdd}>
            <Plus size={14} /> إضافة جهة اتصال
          </button>
        ) : undefined}
      />

      <div style={{ marginTop: 'var(--space-4)' }}>
        {contacts.length === 0 ? (
          <StatePanel
            kind="empty"
            icon={<Users size={38} />}
            title="لا يوجد جهات اتصال"
            description="أضف جهات الاتصال الخاصة بهذا العميل."
            action={canUpdate ? (
              <button type="button" className="btn btn-secondary btn-sm btn-touch" onClick={onAdd}>
                <Plus size={14} /> إضافة أول جهة اتصال
              </button>
            ) : undefined}
            compact
          />
        ) : (
          <div style={collectionGridStyle}>
            {contacts.map(contact => (
              <Card key={contact.id} padding="md" surface={contact.is_primary ? 'elevated' : 'default'}>
                <SectionHeader
                  headingLevel={3}
                  title={contact.name}
                  action={contact.is_primary ? <StatusBadge label="أساسي" tone="info" /> : undefined}
                />

                <div style={{ marginTop: 'var(--space-3)' }}>
                  <KeyValueList
                    columns={1}
                    compact
                    items={[
                      ...(contact.role ? [{ key: 'role', label: 'الوظيفة', value: contact.role }] : []),
                      ...(contact.phone ? [{ key: 'phone', label: 'الهاتف', value: <span dir="ltr">{contact.phone}</span> }] : []),
                      ...(contact.email ? [{ key: 'email', label: 'البريد الإلكتروني', value: <span dir="ltr">{contact.email}</span> }] : []),
                    ]}
                  />
                </div>

                {canUpdate && (
                  <div style={cardActionsStyle}>
                    <button type="button" className="btn btn-ghost btn-sm btn-touch" onClick={() => onEdit(contact)}>
                      <Edit size={14} /> تعديل
                    </button>
                    <button
                      type="button"
                      className="btn btn-danger btn-sm btn-icon btn-touch"
                      aria-label={`حذف جهة الاتصال ${contact.name}`}
                      onClick={() => onDelete(contact.id, contact.name)}
                    >
                      <Trash2 size={14} />
                    </button>
                  </div>
                )}
              </Card>
            ))}
          </div>
        )}
      </div>
    </Card>
  )
}

export interface CustomerCreditHistoryPanelProps {
  history: CustomerCreditHistory[]
}

export function CustomerCreditHistoryPanel({ history }: CustomerCreditHistoryPanelProps) {
  return (
    <Card padding="lg">
      <SectionHeader title="سجل تغييرات الائتمان" icon={<History size={18} />} />

      <div style={{ marginTop: 'var(--space-4)' }}>
        {history.length === 0 ? (
          <StatePanel
            kind="empty"
            icon={<History size={38} />}
            title="لا يوجد تغييرات مسجلة"
            description="سيتم تسجيل التغييرات تلقائياً عند تعديل حد الائتمان."
            compact
          />
        ) : (
          <div style={creditTableScrollerStyle} tabIndex={0} aria-label="سجل تغييرات الائتمان">
            <table className="data-table">
              <thead>
                <tr>
                  <th>التاريخ</th>
                  <th>الحد قبل</th>
                  <th>الحد بعد</th>
                  <th>التغيير</th>
                  <th>بواسطة</th>
                  <th>السبب</th>
                </tr>
              </thead>
              <tbody>
                {history.map(entry => {
                  const diff = entry.limit_after - entry.limit_before
                  return (
                    <tr key={entry.id}>
                      <td style={{ fontSize: 'var(--text-xs)', whiteSpace: 'nowrap' }}>
                        {new Date(entry.created_at).toLocaleDateString('ar-EG-u-nu-latn')}
                        <div style={{ color: 'var(--text-muted)' }}>
                          {new Date(entry.created_at).toLocaleTimeString('ar-EG-u-nu-latn', { hour: '2-digit', minute: '2-digit' })}
                        </div>
                      </td>
                      <td style={{ fontVariantNumeric: 'tabular-nums' }}>{entry.limit_before.toLocaleString('ar-EG-u-nu-latn')}</td>
                      <td style={{ fontWeight: 700, fontVariantNumeric: 'tabular-nums' }}>{entry.limit_after.toLocaleString('ar-EG-u-nu-latn')}</td>
                      <td>
                        <span
                          style={{
                            color: diff > 0 ? 'var(--color-success)' : diff < 0 ? 'var(--color-danger)' : 'var(--text-muted)',
                            fontWeight: 600,
                          }}
                        >
                          {diff > 0 ? '+' : ''}{diff.toLocaleString('ar-EG-u-nu-latn')}
                        </span>
                      </td>
                      <td>{entry.changed_by_profile?.full_name || '—'}</td>
                      <td style={{ color: 'var(--text-secondary)', maxWidth: 200, overflow: 'hidden', textOverflow: 'ellipsis' }}>
                        {entry.reason || '—'}
                      </td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </Card>
  )
}
