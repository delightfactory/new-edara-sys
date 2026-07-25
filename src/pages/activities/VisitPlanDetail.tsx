import { useParams, useNavigate } from 'react-router-dom'
import {
  useVisitPlan, useVisitPlanItems,
  useConfirmVisitPlan, useCancelVisitPlan,
  useConfirmVisitPlanAtomic, useCancelVisitPlanAtomic,
  useAddVisitPlanItem, useUpdateVisitPlanItem,
  useCustomers, useCreateVisitPlan,
  useDeleteVisitPlanItem, useReorderVisitPlanItems,
  useCreateVisitPlanTemplateMutation,
  useSkipVisitItemAtomic,
  useRescheduleVisitItemToDateAtomic,
  useCloseVisitDayMissedAtomic,
  useCreateVisitPlanAtomic,
  useReorderVisitPlanItemsAtomic,
  useAddVisitPlanItemAtomic,
  useDeleteVisitPlanItemAtomic,
  useCurrentEmployee,
} from '@/hooks/useQueryHooks'
import { useCustomerBranches } from '@/hooks/useCustomerBranches'
import { useAuthStore } from '@/stores/auth-store'
import { PERMISSIONS } from '@/lib/permissions/constants'
import { toast } from 'sonner'
import { useState, useRef } from 'react'
import { VISITS_ATOMIC_EXECUTION } from '@/lib/config/features'
import {
  MapPin, CheckCircle, XCircle, Plus, SkipForward,
  Calendar, Clock, ChevronLeft, Copy, Archive,
  Edit3, Trash2, ArrowUp, ArrowDown, Play, Save, X, MoreVertical,
} from 'lucide-react'
import PageHeader from '@/components/shared/PageHeader'
import Button from '@/components/ui/Button'
import PlanItemCard from '@/components/shared/PlanItemCard'
import ActivityStatusBadge from '@/components/shared/ActivityStatusBadge'
import ResponsiveModal from '@/components/ui/ResponsiveModal'
import { CardSkeleton } from '@/components/ui/Skeleton'
import type {
  VisitPlanItemInput, PlanItemPurposeType, PlanPriority,
  VisitPlanItem,
  SkipVisitItemAtomicInput,
  RescheduleVisitItemToDateAtomicInput,
  CloseVisitDayMissedAtomicInput,
  ReorderVisitPlanItemsAtomicInput,
  CreateVisitPlanAtomicInput,
  AddVisitPlanItemAtomicInput,
  DeleteVisitPlanItemAtomicInput,
} from '@/lib/types/activities'

function fmtDate(d: string) {
  return new Date(d).toLocaleDateString('ar-EG-u-nu-latn', { weekday: 'long', day: 'numeric', month: 'long' })
}

function tomorrow(): string {
  const d = new Date()
  d.setDate(d.getDate() + 1)
  return d.toISOString().slice(0, 10)
}

// ── Skip reasons
const SKIP_REASONS = [
  'محل مغلق',
  'العميل غير متاح',
  'تأجيل بطلب العميل',
  'ظروف طارئة',
  'مسافة بعيدة / وقت غير كافٍ',
  'أخرى',
]

export default function VisitPlanDetail() {
  const { id }   = useParams<{ id: string }>()
  const navigate = useNavigate()
  const can      = useAuthStore(s => s.can)

  // ── Modal: Confirm
  const [confirmOpen,  setConfirmOpen]  = useState(false)
  const [cancelOpen,   setCancelOpen]   = useState(false)
  const [cancelReason, setCancelReason] = useState('')
  const [processing,   setProcessing]   = useState(false)

  // ── Modal: Add item
  const [addItemOpen,          setAddItemOpen]          = useState(false)
  const [itemCustomerId,       setItemCustomerId]       = useState('')
  const [itemCustomerBranchId, setItemCustomerBranchId] = useState('')
  const [itemPurposeType,      setItemPurposeType]      = useState<PlanItemPurposeType | ''>('')
  const [itemPriority,         setItemPriority]         = useState<PlanPriority>('normal')
  const [itemPlannedTime,      setItemPlannedTime]      = useState('')
  const [itemDuration,         setItemDuration]         = useState(30)
  const [addingItem,           setAddingItem]           = useState(false)

  // ── Customer branches query for selected customer in Add Modal
  const { branches: customerBranches = [], isLoading: branchesLoading } = useCustomerBranches({
    customerId: itemCustomerId,
    enabled: !!itemCustomerId && addItemOpen,
  })

  // ── Modal: Skip item
  const [skipItem,       setSkipItem]       = useState<VisitPlanItem | null>(null)
  const [skipReason,     setSkipReason]     = useState('')
  const [skipCustom,     setSkipCustom]     = useState('')
  const [skipping,       setSkipping]       = useState(false)

  // ── Modal: Reschedule item
  const [rescheduleItem,   setRescheduleItem]   = useState<VisitPlanItem | null>(null)
  const [rescheduleDate,   setRescheduleDate]   = useState(tomorrow())
  const [rescheduleReason, setRescheduleReason] = useState('')
  const [rescheduling,     setRescheduling]     = useState(false)

  // ── Modal: Bulk Close
  const [bulkCloseOpen, setBulkCloseOpen] = useState(false)
  const [bulkReason,    setBulkReason]    = useState('انتهاء الدوام الزمني')

  // ── Modal: Delete Item Confirm (بدل confirm() الافتراضي للمتصفح)
  const [deleteConfirmItem, setDeleteConfirmItem] = useState<VisitPlanItem | null>(null)
  const [deletingItem,      setDeletingItem]      = useState(false)

  // ── Modal: Clone Plan
  const [cloneOpen, setCloneOpen] = useState(false)
  const [cloneDate, setCloneDate] = useState(tomorrow())

  // ── Mobile overflow menu (secondary actions hidden on desktop via desktop-only-btn)
  const [moreMenuOpen, setMoreMenuOpen] = useState(false)

  // ── Data
  const { data: plan,  isLoading: planLoading  } = useVisitPlan(id)
  const { data: items = [], isLoading: itemsLoading } = useVisitPlanItems(id)
  const { data: customersRes } = useCustomers({ pageSize: 200 })
  const customers = customersRes?.data ?? []

  // ── Mutations
  const confirmPlan   = useConfirmVisitPlan()
  const cancelPlan    = useCancelVisitPlan()
  const confirmPlanAtomic = useConfirmVisitPlanAtomic()
  const cancelPlanAtomic = useCancelVisitPlanAtomic()
  const addPlanItem   = useAddVisitPlanItem()
  const updatePlanItem = useUpdateVisitPlanItem()
  const createPlan        = useCreateVisitPlan()
  const deletePlanItem    = useDeleteVisitPlanItem()
  const reorderMut        = useReorderVisitPlanItems()
  const saveAsTmpl        = useCreateVisitPlanTemplateMutation()
  const skipVisitAtomic   = useSkipVisitItemAtomic()
  const rescheduleAtomic  = useRescheduleVisitItemToDateAtomic()
  const closeMissedAtomic = useCloseVisitDayMissedAtomic()
  const createPlanAtomic   = useCreateVisitPlanAtomic()
  const reorderMutAtomic   = useReorderVisitPlanItemsAtomic()
  const addPlanItemAtomic  = useAddVisitPlanItemAtomic()
  const deletePlanItemAtomic = useDeleteVisitPlanItemAtomic()

  // ── Save as Template state
  const [saveTmplOpen,  setSaveTmplOpen]  = useState(false)
  const [tmplName,      setTmplName]      = useState('')
  const [savingTmpl,    setSavingTmpl]    = useState(false)

  // ── Edit Mode State
  const [editMode, setEditMode] = useState(false)

  // ── Atomic operation and concurrency refs
  const confirmOperationIdRef = useRef<string | null>(null)
  const cancelOperationRef    = useRef<{ operationId: string; reason: string } | null>(null)
  const isMutatingRef         = useRef(false)

  // Wave 1.5 typed refs
  const skipOperationRef = useRef<SkipVisitItemAtomicInput | null>(null)
  const rescheduleOperationRef = useRef<RescheduleVisitItemToDateAtomicInput | null>(null)
  const bulkCloseOperationRef = useRef<CloseVisitDayMissedAtomicInput | null>(null)
  const reorderOperationRef = useRef<ReorderVisitPlanItemsAtomicInput | null>(null)
  const cloneOperationRef = useRef<CreateVisitPlanAtomicInput | null>(null)
  const addItemOperationRef = useRef<AddVisitPlanItemAtomicInput | null>(null)
  const deleteItemOperationRef = useRef<DeleteVisitPlanItemAtomicInput | null>(null)

  // Wave 1.5 distinct mutex lock refs
  const isMutatingSkipRef = useRef(false)
  const isMutatingRescheduleRef = useRef(false)
  const isMutatingBulkCloseRef = useRef(false)
  const isMutatingReorderRef = useRef(false)
  const isMutatingCloneRef = useRef(false)
  const isMutatingAddItemRef = useRef(false)
  const isMutatingDeleteItemRef = useRef(false)

  // ── Permissions
  const { data: currentEmployee } = useCurrentEmployee()
  const isOwnPlan = !!plan && !!currentEmployee && plan.employee_id === currentEmployee.id
  const isDraft = plan?.status === 'draft'

  const canConfirm   = can(PERMISSIONS.VISIT_PLANS_CONFIRM)
  const canCancel    = can(PERMISSIONS.VISIT_PLANS_CANCEL)
  const canCreate    = can(PERMISSIONS.VISIT_PLANS_CREATE)

  const canReorderItems = isDraft && (
    can(PERMISSIONS.VISIT_PLANS_UPDATE) ||
    (isOwnPlan && can(PERMISSIONS.VISIT_PLANS_UPDATE_OWN))
  )

  const canAddItem   = isDraft && can(PERMISSIONS.VISIT_PLANS_CREATE)
  const canDeleteItem = isDraft && can(PERMISSIONS.VISIT_PLANS_CREATE)
  const canSaveTmpl  = can(PERMISSIONS.VISIT_PLANS_CREATE)
  const canSkip      = plan?.status === 'confirmed' || plan?.status === 'in_progress'

  const canManageDraftItems = canReorderItems || canDeleteItem

  // مصفوفة التعديل المرن
  const canEditPlan = canManageDraftItems

  // إنهاء اليومية (Bulk Close)
  const canCloseDayAtomic = can(PERMISSIONS.VISIT_PLANS_CLOSE_ADMINISTRATIVE)
  const canCloseDayLegacy = canConfirm
  const canCloseDay = VISITS_ATOMIC_EXECUTION ? canCloseDayAtomic : canCloseDayLegacy

  // هل يمكن بدء التنفيذ?
  const canExecuteAtomic = can(PERMISSIONS.VISIT_PLANS_UPDATE_OWN) && can(PERMISSIONS.ACTIVITIES_CREATE)
  const canExecuteLegacy = canCreate
  const canExecute = (VISITS_ATOMIC_EXECUTION ? canExecuteAtomic : canExecuteLegacy) &&
    (plan?.status === 'confirmed' || plan?.status === 'in_progress')

  // ── Handlers: Confirm / Cancel
  const handleConfirm = () => {
    if (!id || processing || isMutatingRef.current) return
    isMutatingRef.current = true
    setProcessing(true)
    if (VISITS_ATOMIC_EXECUTION) {
      if (!confirmOperationIdRef.current) {
        confirmOperationIdRef.current = crypto.randomUUID()
      }
      const opId = confirmOperationIdRef.current
      confirmPlanAtomic.mutate({ operationId: opId, planId: id }, {
        onSuccess: () => {
          toast.success('تم تأكيد الخطة ذرياً')
          setConfirmOpen(false)
          confirmOperationIdRef.current = null
        },
        onError:   (err: unknown) => {
          const errMsg = err instanceof Error ? err.message : 'فشلت العملية الذرية للتأكيد'
          toast.error(errMsg)
        },
        onSettled: () => {
          isMutatingRef.current = false
          setProcessing(false)
        },
      })
    } else {
      confirmPlan.mutate(id, {
        onSuccess: () => { toast.success('تم تأكيد الخطة'); setConfirmOpen(false) },
        onError:   () => toast.error('فشل التأكيد'),
        onSettled: () => {
          isMutatingRef.current = false
          setProcessing(false)
        },
      })
    }
  }

  const handleCancel = () => {
    if (!id || processing || isMutatingRef.current) return
    if (VISITS_ATOMIC_EXECUTION) {
      const activeReason = cancelOperationRef.current ? cancelOperationRef.current.reason : cancelReason.trim()
      if (!activeReason) {
        toast.error('سبب الإلغاء إلزامي في المسار الذري')
        return
      }
      isMutatingRef.current = true
      setProcessing(true)

      if (!cancelOperationRef.current) {
        cancelOperationRef.current = {
          operationId: crypto.randomUUID(),
          reason: activeReason
        }
      }
      const { operationId, reason } = cancelOperationRef.current

      cancelPlanAtomic.mutate({ operationId, planId: id, reason }, {
        onSuccess: () => {
          toast.success('تم إلغاء الخطة ذرياً')
          setCancelOpen(false)
          setCancelReason('')
          cancelOperationRef.current = null
        },
        onError:   (err: unknown) => {
          const errMsg = err instanceof Error ? err.message : 'فشلت العملية الذرية للإلغاء'
          toast.error(errMsg)
        },
        onSettled: () => {
          isMutatingRef.current = false
          setProcessing(false)
        },
      })
    } else {
      isMutatingRef.current = true
      setProcessing(true)
      cancelPlan.mutate({ id, reason: cancelReason || undefined }, {
        onSuccess: () => { toast.success('تم إلغاء الخطة'); setCancelOpen(false) },
        onError:   () => toast.error('فشل الإلغاء'),
        onSettled: () => {
          isMutatingRef.current = false
          setProcessing(false)
        },
      })
    }
  }

  // ── Handler: Add Item
  const handleAddItem = () => {
    if (!id || !(addItemOperationRef.current ? addItemOperationRef.current.customerId : itemCustomerId)) { toast.error('اختر العميل'); return }

    if (VISITS_ATOMIC_EXECUTION) {
      if (isMutatingAddItemRef.current) return
      isMutatingAddItemRef.current = true
      setAddingItem(true)

      if (!addItemOperationRef.current) {
        addItemOperationRef.current = {
          operationId: crypto.randomUUID(),
          planId: id,
          customerId: itemCustomerId,
          customerBranchId: itemCustomerBranchId || null,
          purposeType: itemPurposeType || null,
          priority: itemPriority,
          plannedTime: itemPlannedTime || null,
          estimatedDurationMin: itemDuration,
          clientEventAt: new Date().toISOString(),
          deviceTimezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
        }
      }

      addPlanItemAtomic.mutate(addItemOperationRef.current, {
        onSuccess: () => {
          toast.success('تمت إضافة البند ذرياً')
          setAddItemOpen(false)
          setItemCustomerId(''); setItemCustomerBranchId(''); setItemPurposeType('')
          setItemPriority('normal'); setItemPlannedTime(''); setItemDuration(30)
          addItemOperationRef.current = null
        },
        onError: (e: unknown) => {
          toast.error(e instanceof Error ? e.message : 'فشلت إضافة البند ذرياً')
        },
        onSettled: () => {
          isMutatingAddItemRef.current = false
          setAddingItem(false)
        },
      })
      return
    }

    // Legacy Fallback
    setAddingItem(true)
    const itemInput: VisitPlanItemInput = {
      customer_id:            itemCustomerId,
      customer_branch_id:     itemCustomerBranchId || null,
      sequence:               items.length + 1,
      purpose_type:           itemPurposeType || null,
      priority:               itemPriority,
      planned_time:           itemPlannedTime || null,
      estimated_duration_min: itemDuration,
    }
    addPlanItem.mutate(
      { planId: id, item: itemInput },
      {
        onSuccess: () => {
          toast.success('تم إضافة البند')
          setAddItemOpen(false)
          setItemCustomerId(''); setItemCustomerBranchId(''); setItemPurposeType('')
          setItemPriority('normal'); setItemPlannedTime(''); setItemDuration(30)
        },
        onError:   (e: unknown) => toast.error(e instanceof Error ? e.message : 'فشل إضافة البند'),
        onSettled: () => setAddingItem(false),
      }
    )
  }

  // ── Handler: Skip Item
  const handleSkip = () => {
    if (!skipItem || !id) return
    const reason = skipReason === 'أخرى' ? (skipCustom || 'أخرى') : skipReason
    if (!reason) { toast.error('اختر سبب التخطي'); return }

    if (VISITS_ATOMIC_EXECUTION) {
      if (isMutatingSkipRef.current) return
      isMutatingSkipRef.current = true
      setSkipping(true)

      if (!skipOperationRef.current) {
        skipOperationRef.current = {
          operationId: crypto.randomUUID(),
          itemId: skipItem.id,
          skipReason: reason,
          clientEventAt: new Date().toISOString(),
          deviceTimezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
        }
      }

      skipVisitAtomic.mutate(
        {
          planId: id,
          input: skipOperationRef.current
        },
        {
          onSuccess: () => {
            toast.success('تم تخطي البند بنجاح (المسار الذري)')
            setSkipItem(null); setSkipReason(''); setSkipCustom('')
            skipOperationRef.current = null
          },
          onError: (e: unknown) => {
            toast.error(e instanceof Error ? e.message : 'فشل تخطي البند')
          },
          onSettled: () => {
            isMutatingSkipRef.current = false
            setSkipping(false)
          },
        }
      )
      return
    }

    // مسار تقليدي (Fallback)
    setSkipping(true)
    updatePlanItem.mutate(
      {
        itemId: skipItem.id,
        planId:  id,
        input:   { status: 'skipped', skip_reason: reason },
      },
      {
        onSuccess: () => {
          toast.success('تم تخطي البند')
          setSkipItem(null); setSkipReason(''); setSkipCustom('')
        },
        onError:   (e: unknown) => toast.error(e instanceof Error ? e.message : 'فشل تخطي البند'),
        onSettled: () => setSkipping(false),
      }
    )
  }

  // ── Handler: Reschedule Item
  const handleReschedule = () => {
    if (!rescheduleItem || !id || !rescheduleDate) return

    if (VISITS_ATOMIC_EXECUTION && !rescheduleReason.trim()) {
      toast.error('يرجى كتابة سبب إعادة الجدولة')
      return
    }

    if (VISITS_ATOMIC_EXECUTION) {
      if (isMutatingRescheduleRef.current) return
      isMutatingRescheduleRef.current = true
      setRescheduling(true)

      if (!rescheduleOperationRef.current) {
        rescheduleOperationRef.current = {
          operationId: crypto.randomUUID(),
          itemId: rescheduleItem.id,
          targetDate: rescheduleDate,
          rescheduleReason: rescheduleReason.trim(),
          plannedTime: null,
          clientEventAt: new Date().toISOString(),
          deviceTimezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
        }
      }

      rescheduleAtomic.mutate(
        {
          planId: id,
          input: rescheduleOperationRef.current
        },
        {
          onSuccess: () => {
            toast.success(`تمت إعادة الجدولة إلى ${new Date(rescheduleDate).toLocaleDateString('ar-EG-u-nu-latn')} (المسار الذري)`)
            setRescheduleItem(null)
            setRescheduleReason('')
            rescheduleOperationRef.current = null
          },
          onError: (e: unknown) => {
            toast.error(e instanceof Error ? e.message : 'فشل إعادة الجدولة')
          },
          onSettled: () => {
            isMutatingRescheduleRef.current = false
            setRescheduling(false)
          },
        }
      )
      return
    }

    // مسار تقليدي (Fallback)
    setRescheduling(true)
    updatePlanItem.mutate(
      {
        itemId: rescheduleItem.id,
        planId:  id,
        input:   { status: 'rescheduled', reschedule_to: rescheduleDate },
      },
      {
        onSuccess: () => {
          toast.success(`تمت إعادة الجدولة إلى ${new Date(rescheduleDate).toLocaleDateString('ar-EG-u-nu-latn')}`)
          setRescheduleItem(null)
          setRescheduleReason('')
        },
        onError:   (e: unknown) => toast.error(e instanceof Error ? e.message : 'فشل إعادة الجدولة'),
        onSettled: () => setRescheduling(false),
      }
    )
  }

  // ── Handler: Bulk Close
  const pendingItems = items.filter(i => i.status === 'pending')
  const handleBulkClose = async () => {
    if (!id || pendingItems.length === 0) return

    if (VISITS_ATOMIC_EXECUTION) {
      if (isMutatingBulkCloseRef.current) return
      isMutatingBulkCloseRef.current = true
      setProcessing(true)

      if (!bulkCloseOperationRef.current) {
        bulkCloseOperationRef.current = {
          operationId: crypto.randomUUID(),
          planId: id,
          closeReason: bulkReason,
          clientEventAt: new Date().toISOString(),
          deviceTimezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
        }
      }

      closeMissedAtomic.mutate(
        {
          planId: id,
          input: bulkCloseOperationRef.current
        },
        {
          onSuccess: () => {
            toast.success('تم إنهاء اليومية ذرياً بنجاح')
            setBulkCloseOpen(false)
            bulkCloseOperationRef.current = null
          },
          onError: (e: unknown) => {
            toast.error(e instanceof Error ? e.message : 'فشل إنهاء اليومية ذرياً')
          },
          onSettled: () => {
            isMutatingBulkCloseRef.current = false
            setProcessing(false)
          }
        }
      )
      return
    }

    // مسار تقليدي (Fallback)
    setProcessing(true)
    let errs = 0
    for (const item of pendingItems) {
      try {
        await updatePlanItem.mutateAsync({
          itemId: item.id,
          planId: id,
          input: { status: 'missed', skip_reason: bulkReason }
        })
      } catch {
        errs++
      }
    }
    setProcessing(false)
    setBulkCloseOpen(false)
    if (errs > 0) toast.warning(`تم تحويل البعض لزائفة، ولكن فشل ${errs} بند`)
    else toast.success('تم إنهاء اليومية وتحديث البنود المعلقة')
  }

  // ── Handler: Clone Plan
  const handleClone = async () => {
    if (!plan) return
    if (items.length === 0) {
      toast.error('لا يمكن استنساخ خطة فارغة بدون بنود.')
      return
    }

    if (VISITS_ATOMIC_EXECUTION) {
      if (isMutatingCloneRef.current) return
      isMutatingCloneRef.current = true
      setProcessing(true)

      if (!cloneOperationRef.current) {
        const sortedItems = [...items].sort((a, b) => a.sequence - b.sequence)
        const tmplItems = sortedItems.map((item, index) => ({
          customer_id:            item.customer_id,
          customer_branch_id:     item.customer_branch_id ?? null,
          sequence:               index + 1,
          planned_time:           item.planned_time || null,
          estimated_duration_min: item.estimated_duration_min || 30,
          priority:               item.priority,
          purpose_type:           item.purpose_type ?? null,
          purpose:                item.purpose ?? null,
        }))

        cloneOperationRef.current = {
          operationId: crypto.randomUUID(),
          employeeId: plan.employee_id,
          planDate: cloneDate,
          planType: plan.plan_type,
          notes: `نسخة مستنسخة من مسار يوم ${plan.plan_date}`,
          items: tmplItems
        }
      }

      if (!cloneOperationRef.current) return

      createPlanAtomic.mutate(cloneOperationRef.current, {
        onSuccess: (result) => {
          toast.success('تم استنساخ الخطة ذرياً بنجاح')
          setCloneOpen(false)
          setCloneDate(tomorrow())
          cloneOperationRef.current = null
          if (result.ok) {
            navigate(`/activities/visit-plans/${result.data.plan_id}`)
          }
        },
        onError: (e: unknown) => {
          toast.error(e instanceof Error ? e.message : 'فشل استنساخ الخطة ذرياً')
        },
        onSettled: () => {
          isMutatingCloneRef.current = false
          setProcessing(false)
        }
      })
      return
    }

    // مسار تقليدي (Fallback)
    setProcessing(true)
    try {
      const newPlan = await createPlan.mutateAsync({
        employee_id: plan.employee_id,
        plan_date: cloneDate,
        plan_type: plan.plan_type,
        notes: `نسخة مستنسخة من مسار يوم ${plan.plan_date}`,
      })
      
      let copied = 0
      for (const item of items) {
        try {
          await addPlanItem.mutateAsync({
            planId: newPlan.id,
            item: {
              customer_id: item.customer_id,
              sequence: item.sequence,
              purpose_type: item.purpose_type || null,
              priority: item.priority,
              planned_time: item.planned_time || null,
              estimated_duration_min: item.estimated_duration_min || 30,
            }
          })
          copied++
        } catch { /* ignore individual item errors in clone */ }
      }
      
      toast.success(`تم إنشاء نسخة بخطة جديدة (تم نسخ ${copied} بند)`)
      setCloneOpen(false)
      setCloneDate(tomorrow())
      navigate(`/activities/visit-plans/${newPlan.id}`)
    } catch {
      toast.error('فشل استنساخ الخطة')
    }
    setProcessing(false)
  }

  // ── Handler: Reorder
  const handleReorder = (orderedItemIds: string[]) => {
    if (!id) return

    if (VISITS_ATOMIC_EXECUTION) {
      if (isMutatingReorderRef.current) return

      const isRetry = reorderOperationRef.current &&
        reorderOperationRef.current.items.length === orderedItemIds.length &&
        reorderOperationRef.current.items.every((it, idx) => it.item_id === orderedItemIds[idx] && it.sequence === idx + 1)

      if (reorderOperationRef.current && !isRetry) {
        toast.error('يرجى إعادة محاولة الترتيب السابق أولاً، أو إلغاء نية الترتيب المعلقة.')
        return
      }

      isMutatingReorderRef.current = true

      if (!reorderOperationRef.current) {
        const reorderItems = orderedItemIds.map((itemId, idx) => ({
          item_id: itemId,
          sequence: idx + 1
        }))
        reorderOperationRef.current = {
          operationId: crypto.randomUUID(),
          planId: id,
          items: reorderItems
        }
      }

      reorderMutAtomic.mutate(reorderOperationRef.current, {
        onSuccess: () => {
          toast.success('تم إعادة الترتيب ذرياً')
          reorderOperationRef.current = null
        },
        onError: (err: unknown) => {
          const errMsg = err instanceof Error ? err.message : 'فشلت عملية إعادة الترتيب الذرية'
          toast.error(errMsg, {
            action: {
              label: 'إلغاء الحركة المعلقة',
              onClick: () => { reorderOperationRef.current = null }
            }
          })
        },
        onSettled: () => {
          isMutatingReorderRef.current = false
        }
      })
      return
    }

    // Legacy Fallback
    reorderMut.mutate({ planId: id, orderedItemIds })
  }

  // ── Save as Template handler ─────────────────────────────────────
  async function handleSaveAsTemplate() {
    if (!tmplName.trim()) { toast.error('اسم القالب مطلوب'); return }
    if (items.length === 0) { toast.error('لا يوجد بنود في الخطة'); return }
    setSavingTmpl(true)
    try {
      // Build template items from plan items — preserving customer_id, purpose, priority
      const tmplItems = items.map(item => ({
        customer_id:            item.customer_id,
        customer_name:          item.customer?.name || null,
        customer_code:          item.customer?.code || null,
        phone:                  item.customer?.phone || null,
        latitude:               item.customer?.latitude ?? null,
        longitude:              item.customer?.longitude ?? null,
        planned_time:           item.planned_time || null,
        estimated_duration_min: item.estimated_duration_min || 30,
        priority:               item.priority || 'normal',
        purpose_type:           item.purpose_type || null,
        purpose:                item.purpose ?? null,
      }))
      await saveAsTmpl.mutateAsync({
        name:      tmplName.trim(),
        recurrence: 'none',
        is_active:  true,
        items:      tmplItems,
      })
      toast.success(`تم حفظ القالب "${tmplName.trim()}" بـ${items.length} بند`)
      setSaveTmplOpen(false)
    } catch (e: unknown) {
      toast.error(e instanceof Error ? e.message : 'فشل حفظ القالب')
    } finally {
      setSavingTmpl(false)
    }
  }

  // ── Loading
  if (planLoading) {
    return (
      <div className="page-container animate-enter">
        <div className="edara-card" style={{ padding: 'var(--space-6)' }}>
          {[1, 2, 3].map(i => (
            <div key={i} className="skeleton" style={{ height: 24, marginBottom: 'var(--space-3)', width: `${80 - i * 15}%` }} />
          ))}
        </div>
      </div>
    )
  }

  if (!plan) {
    return (
      <div className="page-container animate-enter">
        <div className="empty-state" style={{ padding: 'var(--space-8)' }}>
          <p className="empty-state-title">لم يتم العثور على الخطة</p>
          <Button variant="secondary" onClick={() => navigate('/activities/visit-plans')}>العودة</Button>
        </div>
      </div>
    )
  }

  // counters
  const highPriority = pendingItems.filter(i => i.priority === 'high')

  return (
    <div className="page-container animate-enter">
      <PageHeader
        title={`خطة زيارات — ${fmtDate(plan.plan_date)}`}
        subtitle={plan.employee?.full_name}
        breadcrumbs={[
          { label: 'خطط الزيارات', path: '/activities/visit-plans' },
          { label: fmtDate(plan.plan_date) },
        ]}
        actions={
          <div className="flex gap-2">
            {/* زر بدء التنفيذ */}
            {canExecute && (
              <Button
                onClick={() => navigate(`/activities/visit-plans/${id}/execute`)}
                icon={<Play size={16} />}
                style={{ background: 'var(--color-success)', borderColor: 'var(--color-success)' }}
              >
                بدء التنفيذ
              </Button>
            )}

            {/* زر وضع التعديل */}
            {canEditPlan && !editMode && (
              <Button variant="secondary" icon={<Edit3 size={16} />} onClick={() => setEditMode(true)}>
                تعديل الخطة
              </Button>
            )}
            {editMode && (
              <Button variant="secondary" icon={<X size={16} />} onClick={() => setEditMode(false)}>
                إلغاء التعديل
              </Button>
            )}

            {canAddItem && (
              <Button icon={<Plus size={16} />} variant="secondary" onClick={() => setAddItemOpen(true)}>
                إضافة بند
              </Button>
            )}
            {canConfirm && plan.status === 'draft' && items.length > 0 && (
              <Button onClick={() => setConfirmOpen(true)} icon={<CheckCircle size={16} />}>
                تأكيد واعتماد
              </Button>
            )}
            {canCloseDay && plan.status === 'in_progress' && pendingItems.length > 0 && (
              <Button onClick={() => { setBulkCloseOpen(true); setBulkReason('انتهاء الدوام الزمني'); bulkCloseOperationRef.current = null }} variant="secondary" icon={<Archive size={16} />} className="desktop-only-btn">
                إنهاء اليومية المتبقية
              </Button>
            )}
            {canCreate && (
              <Button onClick={() => { setCloneOpen(true); setCloneDate(tomorrow()); cloneOperationRef.current = null }} variant="secondary" icon={<Copy size={16} />} className="desktop-only-btn">
                استنساخ المسار
              </Button>
            )}
            {/* Wave A: Save as Template — only if plan has items */}
            {canSaveTmpl && items.length > 0 && (
              <Button
                variant="secondary"
                icon={<Save size={16} />}
                className="desktop-only-btn"
                onClick={() => { setTmplName(plan.employee?.full_name ? `خطة ${plan.employee.full_name}` : 'قالب جديد'); setSaveTmplOpen(true) }}
              >
                حفظ كقالب
              </Button>
            )}
            {/* Mobile overflow menu — exposes desktop-only actions on small screens */}
            {(canCreate || canSaveTmpl || (canCloseDay && plan.status === 'in_progress' && pendingItems.length > 0)) && (
              <div className="mobile-overflow-menu">
                <button
                   className="mobile-overflow-menu-btn"
                   onClick={() => setMoreMenuOpen(prev => !prev)}
                   aria-label="المزيد من الإجراءات"
                   aria-expanded={moreMenuOpen}
                >
                  <MoreVertical size={18} />
                </button>
                {moreMenuOpen && (
                  <>
                    <div
                      style={{ position: 'fixed', inset: 0, zIndex: 199 }}
                      onClick={() => setMoreMenuOpen(false)}
                    />
                    <div className="mobile-overflow-dropdown" role="menu">
                      {canCloseDay && plan.status === 'in_progress' && pendingItems.length > 0 && (
                        <button className="mobile-overflow-item" role="menuitem" onClick={() => { setMoreMenuOpen(false); setBulkCloseOpen(true); setBulkReason('انتهاء الدوام الزمني'); bulkCloseOperationRef.current = null }}>
                          <Archive size={16} /> إنهاء اليومية المتبقية
                        </button>
                      )}
                      {canCreate && (
                        <button className="mobile-overflow-item" role="menuitem" onClick={() => { setMoreMenuOpen(false); setCloneOpen(true); setCloneDate(tomorrow()); cloneOperationRef.current = null }}>
                          <Copy size={16} /> استنساخ المسار
                        </button>
                      )}
                      {canSaveTmpl && items.length > 0 && (
                        <button className="mobile-overflow-item" role="menuitem" onClick={() => { setMoreMenuOpen(false); setTmplName(plan.employee?.full_name ? `خطة ${plan.employee.full_name}` : 'قالب جديد'); setSaveTmplOpen(true) }}>
                          <Save size={16} /> حفظ كقالب
                        </button>
                      )}
                    </div>
                  </>
                )}
              </div>
            )}
            {canCancel && (plan.status === 'draft' || plan.status === 'confirmed') && (
              <Button variant="danger" icon={<XCircle size={16} />} onClick={() => { setCancelOpen(true); setCancelReason(''); cancelOperationRef.current = null }} aria-label="إلغاء خطة الزيارات">
                إلغاء
              </Button>
            )}
          </div>
        }
      />

      {/* ── Summary ──────────────────────────────────────────────── */}
      <div className="edara-card vp-summary">
        <div className="vp-summary-item">
          <div className="vp-summary-value">{plan.total_customers}</div>
          <div className="vp-summary-label">إجمالي الزيارات</div>
        </div>
        <div className="vp-summary-item">
          <div className="vp-summary-value" style={{ color: 'var(--color-success)' }}>{plan.completed_count}</div>
          <div className="vp-summary-label">مكتملة</div>
        </div>
        <div className="vp-summary-item">
          <div className="vp-summary-value" style={{ color: 'var(--color-warning)' }}>{plan.skipped_count}</div>
          <div className="vp-summary-label">متخطاة</div>
        </div>
        <div className="vp-summary-item">
          <div className="vp-summary-value" style={{ color: 'var(--text-muted)' }}>{pendingItems.length}</div>
          <div className="vp-summary-label">معلّقة</div>
        </div>
        <div className="vp-summary-item vp-summary-item--status">
          <ActivityStatusBadge planStatus={plan.status} />
        </div>
      </div>

      {/* ── High Priority Alert ──────────────────────────────────── */}
      {highPriority.length > 0 && canSkip && (
        <div className="vp-alert-high">
          <span>⚠</span>
          <span>{highPriority.length} بند عالي الأولوية معلّق</span>
        </div>
      )}

      {/* ── Progress Bar ─────────────────────────────────────────── */}
      <div className="edara-card" style={{ padding: 'var(--space-4)' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 'var(--space-2)', fontSize: 'var(--text-sm)' }}>
          <span style={{ color: 'var(--text-muted)' }}>التقدم</span>
          <span style={{ fontWeight: 700 }}>{plan.completion_pct.toFixed(0)}%</span>
        </div>
        <div style={{ height: 8, background: 'var(--bg-surface-2)', borderRadius: 99, overflow: 'hidden' }}>
          <div style={{
            height: '100%',
            width: `${Math.min(plan.completion_pct, 100)}%`,
            background: plan.completion_pct >= 100 ? 'var(--color-success)' : 'var(--color-primary)',
            borderRadius: 99,
            transition: 'width 0.5s ease',
          }} />
        </div>
      </div>

      {/* ── Plan Items ───────────────────────────────────────────── */}
      <div className="vp-items">
        {itemsLoading ? (
          [1, 2, 3].map(i => <CardSkeleton key={i} />)
        ) : items.length === 0 ? (
          <div className="empty-state" style={{ padding: 'var(--space-6)' }}>
            <MapPin size={36} className="empty-state-icon" />
            <p className="empty-state-title">لا توجد بنود في هذه الخطة</p>
            {canAddItem && (
              <Button icon={<Plus size={14} />} variant="secondary" onClick={() => setAddItemOpen(true)}>
                إضافة أول بند
              </Button>
            )}
          </div>
        ) : (
          items.map((item, idx) => (
            <div key={item.id} className="vp-item-wrapper">
              {/* Edit mode controls */}
              {editMode && canManageDraftItems && (
                <div className="vp-edit-controls">
                  {canReorderItems && (
                    <>
                      <button
                        className="vp-edit-btn"
                        disabled={idx === 0 || isMutatingReorderRef.current}
                        onClick={() => {
                          const ids = items.map(i => i.id)
                          ;[ids[idx - 1], ids[idx]] = [ids[idx], ids[idx - 1]]
                          handleReorder(ids)
                        }}
                        title="تحريك للأعلى"
                      >
                        <ArrowUp size={14} />
                      </button>
                      <span className="vp-edit-seq">{idx + 1}</span>
                      <button
                        className="vp-edit-btn"
                        disabled={idx === items.length - 1 || isMutatingReorderRef.current}
                        onClick={() => {
                          const ids = items.map(i => i.id)
                          ;[ids[idx], ids[idx + 1]] = [ids[idx + 1], ids[idx]]
                          handleReorder(ids)
                        }}
                        title="تحريك للأسفل"
                      >
                        <ArrowDown size={14} />
                      </button>
                    </>
                  )}
                  {canDeleteItem && (
                    <button
                      className="vp-edit-btn vp-edit-btn--delete"
                      onClick={() => setDeleteConfirmItem(item)}
                      title="حذف البند"
                      disabled={deletingItem}
                    >
                      <Trash2 size={14} />
                    </button>
                  )}
                </div>
              )}
              <PlanItemCard
                item={item}
                type="visit"
                onStart={canExecute && item.status === 'pending' ? () => navigate(
                  `/activities/visit-plans/${id}/execute`
                ) : undefined}
                onViewActivity={item.activity_id ? () => navigate(`/activities/${item.activity_id}`) : undefined}
              />
              {/* Skip + Reschedule */}
              {canSkip && item.status === 'pending' && (
                <div className="vp-item-actions">
                  <button
                    className="vp-action-btn vp-action-btn--skip"
                    onClick={() => { setSkipItem(item); setSkipReason(''); setSkipCustom(''); skipOperationRef.current = null }}
                  >
                    <SkipForward size={13} />
                    تخطي
                  </button>
                  <button
                    className="vp-action-btn vp-action-btn--reschedule"
                    onClick={() => { setRescheduleItem(item); setRescheduleDate(tomorrow()); setRescheduleReason(''); rescheduleOperationRef.current = null }}
                  >
                    <Calendar size={13} />
                    إعادة جدولة
                  </button>
                  {item.planned_time && (
                    <span className="vp-item-time">
                      <Clock size={12} />
                      {item.planned_time}
                    </span>
                  )}
                </div>
              )}
              {/* Reschedule info */}
              {item.status === 'rescheduled' && item.reschedule_to && (
                <div className="vp-item-reschedule-badge">
                  <Calendar size={11} />
                  أُعيدت جدولته إلى: {new Date(item.reschedule_to).toLocaleDateString('ar-EG-u-nu-latn')}
                </div>
              )}
              {/* Skip reason */}
              {item.status === 'skipped' && item.skip_reason && (
                <div className="vp-item-skip-badge">
                  <XCircle size={11} />
                  سبب التخطي: {item.skip_reason}
                </div>
              )}
            </div>
          ))
        )}
      </div>

      {/* ─── Modal: إضافة بند ─── */}
      <ResponsiveModal
        open={addItemOpen}
        onClose={() => {
          if (!addingItem) {
            setAddItemOpen(false)
            setItemCustomerId('')
            setItemCustomerBranchId('')
            addItemOperationRef.current = null
          }
        }}
        title="إضافة بند زيارة"
        disableOverlayClose={addingItem}
        footer={<>
          <Button variant="secondary" onClick={() => { setAddItemOpen(false); setItemCustomerId(''); setItemCustomerBranchId(''); addItemOperationRef.current = null }} disabled={addingItem}>إلغاء</Button>
          <Button onClick={handleAddItem} disabled={addingItem || !(addItemOperationRef.current ? addItemOperationRef.current.customerId : itemCustomerId)}>
            {addingItem ? 'جاري الإضافة...' : 'إضافة'}
          </Button>
        </>}
      >
        <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
          <div className="form-group">
            <label className="form-label">العميل <span className="form-required">*</span></label>
            <select
              className="form-select"
              value={addItemOperationRef.current ? addItemOperationRef.current.customerId : itemCustomerId}
              onChange={e => { setItemCustomerId(e.target.value); setItemCustomerBranchId('') }}
              disabled={addingItem || !!addItemOperationRef.current}
            >
              <option value="">-- اختر العميل --</option>
              {customers.map(c => (
                <option key={c.id} value={c.id}>{c.name}{c.code ? ` (${c.code})` : ''}</option>
              ))}
            </select>
          </div>

          {itemCustomerId && (
            <div className="form-group">
              <label className="form-label">فرع العميل (موقع الزيارة)</label>
              {branchesLoading ? (
                <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>جاري تحميل الفروع...</div>
              ) : (
                <select
                  className="form-select"
                  value={addItemOperationRef.current ? addItemOperationRef.current.customerBranchId ?? '' : itemCustomerBranchId}
                  onChange={e => setItemCustomerBranchId(e.target.value)}
                  disabled={addingItem || !!addItemOperationRef.current}
                >
                  <option value="">الموقع الرئيسي للعميل</option>
                  {customerBranches.map(b => (
                    <option key={b.id} value={b.id}>{b.name}{b.is_primary ? ' (الرئيسي)' : ''}</option>
                  ))}
                </select>
              )}
            </div>
          )}

          <div className="form-group">
            <label className="form-label">الغرض</label>
            <select
              className="form-select"
              value={addItemOperationRef.current ? addItemOperationRef.current.purposeType ?? '' : itemPurposeType}
              onChange={e => setItemPurposeType(e.target.value as PlanItemPurposeType)}
              disabled={addingItem || !!addItemOperationRef.current}
            >
              <option value="">-- غير محدد --</option>
              <option value="sales">مبيعات</option>
              <option value="collection">تحصيل</option>
              <option value="activation">تنشيط</option>
              <option value="promotion">ترويج</option>
              <option value="followup">متابعة</option>
              <option value="service">خدمة</option>
            </select>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="form-group">
              <label className="form-label">الأولوية</label>
              <select
                className="form-select"
                value={addItemOperationRef.current ? addItemOperationRef.current.priority : itemPriority}
                onChange={e => setItemPriority(e.target.value as PlanPriority)}
                disabled={addingItem || !!addItemOperationRef.current}
              >
                <option value="high">عالية</option>
                <option value="normal">عادية</option>
                <option value="low">منخفضة</option>
              </select>
            </div>
            <div className="form-group">
              <label className="form-label">الوقت المخطط</label>
              <input
                type="time"
                className="form-input"
                value={addItemOperationRef.current ? addItemOperationRef.current.plannedTime ?? '' : itemPlannedTime}
                onChange={e => setItemPlannedTime(e.target.value)}
                disabled={addingItem || !!addItemOperationRef.current}
              />
            </div>
          </div>
          <div className="form-group">
            <label className="form-label">المدة المتوقعة (دقيقة)</label>
            <input
              type="number"
              className="form-input"
              value={addItemOperationRef.current ? addItemOperationRef.current.estimatedDurationMin : itemDuration}
              min={5}
              max={480}
              onChange={e => setItemDuration(Number(e.target.value))}
              disabled={addingItem || !!addItemOperationRef.current}
            />
          </div>
        </div>
      </ResponsiveModal>

      {/* ─── Modal: Skip ─── */}
      <ResponsiveModal
        open={!!skipItem}
        onClose={() => { if (!skipping) { setSkipItem(null); setSkipReason(''); setSkipCustom(''); skipOperationRef.current = null } }}
        title={`تخطي: ${skipItem?.customer?.name ?? '...'}`}
        disableOverlayClose={skipping}
        footer={<>
          <Button variant="secondary" onClick={() => { setSkipItem(null); setSkipReason(''); setSkipCustom(''); skipOperationRef.current = null }} disabled={skipping}>إلغاء</Button>
          <Button variant="danger" onClick={handleSkip} disabled={skipping || !(skipOperationRef.current ? skipOperationRef.current.skipReason : skipReason)}>
            {skipping ? 'جاري التخطي...' : 'تخطي البند'}
          </Button>
        </>}
      >
        <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-3)' }}>
          <p style={{ margin: 0, fontSize: 'var(--text-sm)', color: 'var(--text-secondary)' }}>
            اختر سبب تخطي هذه الزيارة — سيُسجَّل للمراجعة.
          </p>
          <div className="vp-skip-reasons">
            {SKIP_REASONS.map(r => {
              const activeVal = skipOperationRef.current ? skipOperationRef.current.skipReason : skipReason
              const isSelected = activeVal === r || (r === 'أخرى' && activeVal && !SKIP_REASONS.includes(activeVal))
              return (
                <button
                  key={r}
                  type="button"
                  className={`vp-skip-reason-btn${isSelected ? ' vp-skip-reason-btn--active' : ''}`}
                  onClick={() => setSkipReason(r)}
                  disabled={skipping || !!skipOperationRef.current}
                >
                  {r}
                </button>
              )
            })}
          </div>
          {((skipOperationRef.current ? skipOperationRef.current.skipReason : skipReason) === 'أخرى' || (skipOperationRef.current && !SKIP_REASONS.includes(skipOperationRef.current.skipReason))) && (
            <div className="form-group">
              <label className="form-label">اذكر السبب</label>
              <input
                className="form-input"
                value={skipOperationRef.current ? skipOperationRef.current.skipReason : skipCustom}
                onChange={e => setSkipCustom(e.target.value)}
                placeholder="سبب التخطي..."
                disabled={skipping || !!skipOperationRef.current}
                autoFocus
              />
            </div>
          )}
        </div>
      </ResponsiveModal>

      {/* ─── Modal: Reschedule ─── */}
      <ResponsiveModal
        open={!!rescheduleItem}
        onClose={() => { if (!rescheduling) { setRescheduleItem(null); setRescheduleReason(''); rescheduleOperationRef.current = null } }}
        title={`إعادة جدولة: ${rescheduleItem?.customer?.name ?? '...'}`}
        disableOverlayClose={rescheduling}
        footer={<>
          <Button variant="secondary" onClick={() => { setRescheduleItem(null); setRescheduleReason(''); rescheduleOperationRef.current = null }} disabled={rescheduling}>إلغاء</Button>
          <Button onClick={handleReschedule} disabled={rescheduling || !(rescheduleOperationRef.current ? rescheduleOperationRef.current.targetDate : rescheduleDate)}>
            {rescheduling ? 'جاري الجدولة...' : 'تأكيد إعادة الجدولة'}
          </Button>
        </>}
      >
        <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
          <p style={{ margin: 0, fontSize: 'var(--text-sm)', color: 'var(--text-secondary)', lineHeight: 1.7 }}>
            اختر تاريخاً جديداً لزيارة <strong>{rescheduleItem?.customer?.name}</strong>.
            سيُحوَّل البند تلقائياً إلى خطة اليوم الجديد لنفس المندوب.
          </p>
          <div className="vp-modal-hint">
            💡 إعادة الجدولة تُغيّر حالة هذا البند إلى "معاد جدولته" ولا تحذف البند الأصلي.
          </div>
          <div className="form-group">
            <label className="form-label">التاريخ الجديد <span className="form-required">*</span></label>
            <input
              type="date"
              className="form-input"
              value={rescheduleOperationRef.current ? rescheduleOperationRef.current.targetDate : rescheduleDate}
              min={tomorrow()}
              onChange={e => setRescheduleDate(e.target.value)}
              disabled={rescheduling || !!rescheduleOperationRef.current}
            />
          </div>
          <div className="form-group">
            <label className="form-label">سبب التعديل {VISITS_ATOMIC_EXECUTION && <span className="form-required">*</span>}</label>
            <textarea
              className="form-input"
              rows={3}
              value={rescheduleOperationRef.current ? rescheduleOperationRef.current.rescheduleReason : rescheduleReason}
              onChange={e => setRescheduleReason(e.target.value)}
              placeholder="اكتب سبب إعادة الجدولة..."
              disabled={rescheduling || !!rescheduleOperationRef.current}
            />
          </div>
        </div>
      </ResponsiveModal>

      {/* ─── Modal: تأكيد الخطة ─── */}
      <ResponsiveModal open={confirmOpen} onClose={() => { setConfirmOpen(false); confirmOperationIdRef.current = null }} title="تأكيد خطة الزيارات"
        disableOverlayClose={processing}
        footer={<>
          <Button variant="secondary" onClick={() => { setConfirmOpen(false); confirmOperationIdRef.current = null }} disabled={processing}>إلغاء</Button>
          <Button variant="success" onClick={handleConfirm} disabled={processing}>
            {processing ? 'جاري التأكيد...' : 'تأكيد'}
          </Button>
        </>}>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-3)' }}>
          <p style={{ margin: 0, color: 'var(--text-secondary)', fontSize: 'var(--text-sm)', lineHeight: 1.7 }}>
            تأكيد خطة <strong>{fmtDate(plan.plan_date)}</strong> بـ <strong>{items.length}</strong> {items.length === 1 ? 'زيارة' : 'زيارات'}؟
          </p>
          <div className="vp-modal-hint vp-modal-hint--warning">
            ⚠ بعد التأكيد لن تتمكن من إضافة أو تعديل البنود. تأكد من مراجعة جميع العملاء.
          </div>
        </div>
      </ResponsiveModal>

      {/* ─── Modal: إلغاء الخطة ─── */}
      <ResponsiveModal open={cancelOpen} onClose={() => { setCancelOpen(false); setCancelReason(''); cancelOperationRef.current = null }} title="إلغاء خطة الزيارات"
        disableOverlayClose={processing}
        footer={<>
          <Button variant="secondary" onClick={() => { setCancelOpen(false); setCancelReason(''); cancelOperationRef.current = null }} disabled={processing}>تراجع</Button>
          <Button variant="danger" onClick={handleCancel} disabled={processing}>
            {processing ? 'جاري الإلغاء...' : 'إلغاء الخطة'}
          </Button>
        </>}>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-3)' }}>
          <p style={{ margin: 0, color: 'var(--text-secondary)', fontSize: 'var(--text-sm)' }}>
            إلغاء خطة {fmtDate(plan.plan_date)}؟ الزيارات المنجزة تبقى كما هي.
          </p>
          <div className="form-group">
            <label className="form-label">سبب الإلغاء (مطلوب)</label>
            <textarea
              className="form-textarea"
              rows={2}
              value={cancelOperationRef.current ? cancelOperationRef.current.reason : cancelReason}
              onChange={e => setCancelReason(e.target.value)}
              placeholder="اذكر سبب الإلغاء وجوباً..."
              disabled={processing || !!cancelOperationRef.current}
            />
          </div>
        </div>
      </ResponsiveModal>

      {/* ─── Modal: Bulk Close ─── */}
      <ResponsiveModal
        open={bulkCloseOpen}
        onClose={() => { if (!processing) { setBulkCloseOpen(false); setBulkReason('انتهاء الدوام الزمني'); bulkCloseOperationRef.current = null } }}
        title="إنهاء يومية الخطة وتحويل المعلقات"
        disableOverlayClose={processing}
        footer={<>
          <Button variant="secondary" onClick={() => { setBulkCloseOpen(false); setBulkReason('انتهاء الدوام الزمني'); bulkCloseOperationRef.current = null }} disabled={processing}>إلغاء</Button>
          <Button onClick={handleBulkClose} disabled={processing || !(bulkCloseOperationRef.current ? bulkCloseOperationRef.current.closeReason : bulkReason).trim()}>
            {processing ? 'جاري التنفيذ...' : 'تسجيل كافة المعلقات كزيارات فائتة'}
          </Button>
        </>}
      >
        <div style={{ padding: 'var(--space-2) 0', display: 'flex', flexDirection: 'column', gap: 'var(--space-3)' }}>
          <p style={{ margin: 0, fontSize: 'var(--text-sm)', color: 'var(--text-secondary)' }}>
            يوجد <strong>{pendingItems.length}</strong> {pendingItems.length === 1 ? 'بند معلق' : 'بنود معلقة'}.
            سيتم تسجيلها جميعاً كـ <strong>زيارات فائتة</strong> وإغلاق الخطة.
          </p>
          <div className="vp-modal-hint vp-modal-hint--warning">
            ⚠ هذا الإجراء لا يمكن التراجع عنه. ستظل الزيارات المنجزة سليمة.
          </div>
          <div className="form-group" style={{ margin: 0 }}>
            <label className="form-label">سبب إغلاق البنود المتبقية <span className="form-required">*</span></label>
            <input
              className="form-input"
              value={bulkCloseOperationRef.current ? bulkCloseOperationRef.current.closeReason : bulkReason}
              onChange={e => setBulkReason(e.target.value)}
              placeholder="مثال: انتهاء الدوام، ظروف جوية، مشكلة طارئة..."
              disabled={processing || !!bulkCloseOperationRef.current}
            />
          </div>
        </div>
      </ResponsiveModal>

      {/* ─── Modal: Clone Plan ─── */}
      <ResponsiveModal
        open={cloneOpen}
        onClose={() => { if (!processing) { setCloneOpen(false); setCloneDate(tomorrow()); cloneOperationRef.current = null } }}
        title="استنساخ مسار خطة الزيارات"
        disableOverlayClose={processing}
        footer={<>
          <Button variant="secondary" onClick={() => { setCloneOpen(false); setCloneDate(tomorrow()); cloneOperationRef.current = null }} disabled={processing}>إلغاء</Button>
          <Button onClick={handleClone} disabled={processing || !(cloneOperationRef.current ? cloneOperationRef.current.planDate : cloneDate)}>
            {processing ? 'جاري الاستنساخ...' : 'تأكيد العملية'}
          </Button>
        </>}
      >
        <div style={{ padding: 'var(--space-2) 0' }}>
          <p style={{ margin: '0 0 var(--space-4)', fontSize: 'var(--text-sm)', color: 'var(--text-secondary)' }}>
            سيتم استنساخ هذه الخطة ومسار العملاء لليوم الذي تختاره لمندوبك: <strong>{plan.employee?.full_name}</strong>. ستكون النسخة مسودة قابلة للتعديل.
          </p>
          <div className="form-group">
            <label className="form-label">تاريخ الخطة الجديدة <span className="form-required">*</span></label>
            <input
              type="date"
              className="form-input"
              value={cloneOperationRef.current ? cloneOperationRef.current.planDate : cloneDate}
              onChange={e => setCloneDate(e.target.value)}
              disabled={processing || !!cloneOperationRef.current}
              required
            />
          </div>
        </div>
      </ResponsiveModal>

      {/* ─── Modal: تأكيد حذف بند (بديل confirm() الافتراضي) ─── */}
      <ResponsiveModal
        open={!!deleteConfirmItem}
        onClose={() => { if (!deletingItem) { setDeleteConfirmItem(null); deleteItemOperationRef.current = null } }}
        title="تأكيد حذف البند"
        disableOverlayClose={deletingItem}
        footer={<>
          <Button variant="secondary" onClick={() => { setDeleteConfirmItem(null); deleteItemOperationRef.current = null }} disabled={deletingItem}>إلغاء</Button>
          <Button
            variant="danger"
            disabled={deletingItem}
            onClick={() => {
              if (!deleteConfirmItem || !id) return

              if (VISITS_ATOMIC_EXECUTION) {
                if (isMutatingDeleteItemRef.current) return
                isMutatingDeleteItemRef.current = true
                setDeletingItem(true)

                if (!deleteItemOperationRef.current) {
                  deleteItemOperationRef.current = {
                    operationId: crypto.randomUUID(),
                    itemId: deleteConfirmItem.id,
                    clientEventAt: new Date().toISOString(),
                    deviceTimezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
                  }
                }

                deletePlanItemAtomic.mutate(
                  {
                    input: deleteItemOperationRef.current,
                    planId: id,
                  },
                  {
                    onSuccess: () => {
                      toast.success('تم حذف البند ذرياً بنجاح')
                      setDeleteConfirmItem(null)
                      deleteItemOperationRef.current = null
                    },
                    onError: (e: unknown) => {
                      toast.error(e instanceof Error ? e.message : 'فشل حذف البند ذرياً')
                    },
                    onSettled: () => {
                      isMutatingDeleteItemRef.current = false
                      setDeletingItem(false)
                    },
                  }
                )
                return
              }

              // Legacy Fallback
              setDeletingItem(true)
              deletePlanItem.mutate(deleteConfirmItem.id, {
                onSuccess: () => {
                  toast.success('تم حذف البند بنجاح')
                  setDeleteConfirmItem(null)
                },
                onError: () => toast.error('فشل حذف البند'),
                onSettled: () => setDeletingItem(false),
              })
            }}
          >
            {deletingItem ? 'جاري الحذف...' : 'حذف البند'}
          </Button>
        </>}
      >
        <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-3)' }}>
          <p style={{ margin: 0, color: 'var(--text-secondary)', fontSize: 'var(--text-sm)', lineHeight: 1.7 }}>
            هل تريد حذف زيارة <strong>{deleteConfirmItem?.customer?.name}</strong> من الخطة؟
          </p>
          <div className="vp-modal-hint vp-modal-hint--danger">
            ⚠ سيتم حذف هذا البند نهائياً ولا يمكن استرداده.
          </div>
        </div>
      </ResponsiveModal>

      <style>{`
        .vp-summary {
          display: grid;
          grid-template-columns: repeat(4, 1fr) auto;
          gap: var(--space-4);
          padding: var(--space-4);
          align-items: center;
        }
        .vp-summary-item { text-align: center; }
        .vp-summary-value { font-size: var(--text-xl); font-weight: 700; }
        .vp-summary-label { font-size: var(--text-xs); color: var(--text-muted); margin-top: 2px; }
        .vp-alert-high {
          display: flex;
          align-items: center;
          gap: var(--space-2);
          padding: var(--space-3) var(--space-4);
          background: var(--color-warning-light);
          border: 1px solid var(--color-warning);
          border-radius: var(--radius-md);
          font-size: var(--text-sm);
          font-weight: 600;
          color: var(--color-warning);
        }
        /* ── Modal hints (Quick Wins UX) ── */
        .vp-modal-hint {
          font-size: var(--text-xs);
          padding: var(--space-2) var(--space-3);
          border-radius: var(--radius-md);
          line-height: 1.6;
          background: var(--color-primary-light);
          color: var(--color-primary);
          border: 1px solid rgba(37,99,235,0.2);
        }
        .vp-modal-hint--warning {
          background: var(--color-warning-light);
          color: var(--color-warning);
          border-color: rgba(217,119,6,0.25);
        }
        .vp-modal-hint--danger {
          background: var(--color-danger-light);
          color: var(--color-danger);
          border-color: rgba(220,38,38,0.2);
        }
        .vp-items {
          display: flex;
          flex-direction: column;
          gap: var(--space-3);
          margin-top: var(--space-4);
        }
        .vp-item-wrapper {
          display: flex;
          flex-direction: column;
          gap: 0;
        }
        .vp-item-actions {
          display: flex;
          align-items: center;
          gap: var(--space-2);
          padding: var(--space-2) var(--space-3);
          background: var(--bg-surface-2);
          border: 1px solid var(--border-primary);
          border-top: none;
          border-radius: 0 0 var(--radius-md) var(--radius-md);
          flex-wrap: wrap;
        }
        .vp-action-btn {
          display: inline-flex;
          align-items: center;
          gap: 4px;
          padding: 4px 10px;
          border-radius: var(--radius-sm);
          font-size: var(--text-xs);
          font-weight: 600;
          cursor: pointer;
          border: 1px solid;
          transition: all var(--transition-fast);
          font-family: inherit;
        }
        .vp-action-btn--skip {
          background: var(--color-warning-light);
          border-color: var(--color-warning);
          color: var(--color-warning);
        }
        .vp-action-btn--skip:hover { background: var(--color-warning); color: #fff; }
        .vp-action-btn--reschedule {
          background: var(--color-primary-light);
          border-color: var(--color-primary);
          color: var(--color-primary);
        }
        .vp-action-btn--reschedule:hover { background: var(--color-primary); color: #fff; }
        .vp-item-time {
          display: inline-flex;
          align-items: center;
          gap: 4px;
          font-size: var(--text-xs);
          color: var(--text-muted);
          margin-inline-start: auto;
        }
        .vp-item-reschedule-badge,
        .vp-item-skip-badge {
          display: flex;
          align-items: center;
          gap: 4px;
          font-size: 11px;
          padding: 3px var(--space-3);
          border-radius: 0 0 var(--radius-md) var(--radius-md);
          border: 1px solid;
          border-top: none;
        }
        .vp-item-reschedule-badge {
          background: var(--color-primary-light);
          border-color: var(--color-primary);
          color: var(--color-primary);
        }
        .vp-item-skip-badge {
          background: var(--color-warning-light);
          border-color: var(--color-warning);
          color: var(--color-warning);
        }
        /* Skip reasons grid */
        .vp-skip-reasons {
          display: grid;
          grid-template-columns: 1fr 1fr;
          gap: var(--space-2);
        }
        .vp-skip-reason-btn {
          padding: var(--space-2) var(--space-3);
          border: 1px solid var(--border-primary);
          border-radius: var(--radius-md);
          background: var(--bg-surface);
          color: var(--text-secondary);
          font-size: var(--text-sm);
          cursor: pointer;
          transition: all var(--transition-fast);
          font-family: inherit;
          text-align: center;
        }
        .vp-skip-reason-btn:hover { border-color: var(--color-warning); color: var(--color-warning); }
        .vp-skip-reason-btn--active {
          border-color: var(--color-warning);
          background: var(--color-warning);
          color: #fff;
          font-weight: 600;
        }
        /* Edit mode controls */
        .vp-edit-controls {
          display: flex;
          align-items: center;
          gap: var(--space-1);
          padding: var(--space-2) var(--space-3);
          background: var(--color-primary-light);
          border-radius: var(--radius-md) var(--radius-md) 0 0;
          border: 1px solid rgba(37,99,235,0.15);
          border-bottom: none;
        }
        .vp-edit-btn {
          display: inline-flex;
          align-items: center;
          justify-content: center;
          width: 28px;
          height: 28px;
          border: 1px solid var(--border-light);
          border-radius: var(--radius-sm);
          background: var(--bg-surface);
          cursor: pointer;
          color: var(--text-secondary);
          transition: all 0.15s ease;
          padding: 0;
        }
        .vp-edit-btn:hover:not(:disabled) {
          border-color: var(--color-primary);
          color: var(--color-primary);
          background: white;
        }
        .vp-edit-btn:disabled {
          opacity: 0.3;
          cursor: not-allowed;
        }
        .vp-edit-btn--delete {
          margin-inline-start: auto;
        }
        .vp-edit-btn--delete:hover:not(:disabled) {
          border-color: var(--color-danger);
          color: var(--color-danger);
          background: var(--color-danger-light);
        }
        .vp-edit-seq {
          display: inline-flex;
          align-items: center;
          justify-content: center;
          width: 22px;
          height: 22px;
          background: var(--color-primary);
          color: white;
          border-radius: 50%;
          font-size: 11px;
          font-weight: 700;
        }
        @media (max-width: 768px) {
          .vp-summary { grid-template-columns: repeat(2, 1fr); }
          .vp-skip-reasons { grid-template-columns: 1fr; }
        }
      `}</style>

      {/* ── Wave A: Save as Template Modal ─────────────────────── */}
      <ResponsiveModal
        open={saveTmplOpen}
        onClose={() => setSaveTmplOpen(false)}
        title="حفظ الخطة كقالب"
      >
        <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
          <div className="form-group">
            <label className="form-label">اسم القالب <span className="form-required">*</span></label>
            <input
              className="form-input"
              value={tmplName}
              onChange={e => setTmplName(e.target.value)}
              placeholder="مثال: خطة مبيعات القاهرة الأسبوعية"
              autoFocus
            />
          </div>
          <div style={{ fontSize: 'var(--text-sm)', color: 'var(--text-muted)', padding: 'var(--space-2)', background: 'rgba(0,0,0,.04)', borderRadius: 'var(--radius-md)' }}>
            سيتم حفظ خطة {items.length} بند كقالب جديد.
            يمكن تحميله مجدداً عند إنشاء خطة زيارات جديدة.
          </div>
          <div style={{ display: 'flex', gap: 'var(--space-3)', justifyContent: 'flex-end' }}>
            <Button variant="secondary" onClick={() => setSaveTmplOpen(false)}>إلغاء</Button>
            <Button onClick={handleSaveAsTemplate} disabled={savingTmpl}>
              {savingTmpl ? 'جاري الحفظ...' : 'حفظ القالب'}
            </Button>
          </div>
        </div>
      </ResponsiveModal>
    </div>
  )
}
