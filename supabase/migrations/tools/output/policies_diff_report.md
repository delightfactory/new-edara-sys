# RLS Policies Diff Report
> Generated: 2026-04-04T15:58:16.253Z
> Source: pg_policies (live database)

---

## Summary

| Status | Count |
|--------|-------|
| Transformed | **258** |
| No change needed | 2 |
| Skipped (service_role/anon) | 1 |
| Total | 261 |

---

## Transformed Policies (258)

### `activities` — `acts_insert`

**WITH CHECK before:**
```sql
((employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.user_id = auth.uid()))) AND (created_by = auth.uid()) AND check_permission(auth.uid(), 'activities.create'::text))
```

**WITH CHECK after:**
```sql
((employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.user_id = (SELECT auth.uid())))) AND (created_by = (SELECT auth.uid())) AND (SELECT check_permission((SELECT auth.uid()), 'activities.create'::text)))
```

---

### `activities` — `acts_read`

**USING before:**
```sql
((employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.user_id = auth.uid()))) OR (check_permission(auth.uid(), 'activities.read_team'::text) AND (employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.branch_id = ( SELECT hr_employees_1.branch_id
           FROM hr_employees hr_employees_1
          WHERE (hr_employees_1.user_id = auth.uid())
         LIMIT 1))))) OR check_permission(auth.uid(), 'activities.read_all'::text))
```

**USING after:**
```sql
((employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.user_id = (SELECT auth.uid())))) OR ((SELECT check_permission((SELECT auth.uid()), 'activities.read_team'::text)) AND (employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.branch_id = ( SELECT hr_employees_1.branch_id
           FROM hr_employees hr_employees_1
          WHERE (hr_employees_1.user_id = (SELECT auth.uid()))
         LIMIT 1))))) OR (SELECT check_permission((SELECT auth.uid()), 'activities.read_all'::text)))
```

---

### `activities` — `acts_update`

**USING before:**
```sql
(((employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.user_id = auth.uid()))) AND check_permission(auth.uid(), 'activities.update_own'::text) AND (created_at > (now() - '24:00:00'::interval))) OR check_permission(auth.uid(), 'activities.read_all'::text))
```

**USING after:**
```sql
(((employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.user_id = (SELECT auth.uid())))) AND (SELECT check_permission((SELECT auth.uid()), 'activities.update_own'::text)) AND (created_at > (now() - '24:00:00'::interval))) OR (SELECT check_permission((SELECT auth.uid()), 'activities.read_all'::text)))
```

---

### `activity_types` — `act_types_read`

**USING before:**
```sql
(auth.uid() IS NOT NULL)
```

**USING after:**
```sql
((SELECT auth.uid()) IS NOT NULL)
```

---

### `activity_types` — `act_types_write`

**USING before:**
```sql
check_permission(auth.uid(), 'settings.update'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'settings.update'::text))
```

---

### `activity_types` — `activity_types_read`

**USING before:**
```sql
(auth.uid() IS NOT NULL)
```

**USING after:**
```sql
((SELECT auth.uid()) IS NOT NULL)
```

---

### `approval_rules` — `approval_rules_read`

**USING before:**
```sql
(auth.uid() IS NOT NULL)
```

**USING after:**
```sql
((SELECT auth.uid()) IS NOT NULL)
```

---

### `approval_rules` — `approval_rules_write`

**USING before:**
```sql
check_permission(auth.uid(), 'settings.update'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'settings.update'::text))
```

---

### `areas` — `areas_read`

**USING before:**
```sql
(auth.uid() IS NOT NULL)
```

**USING after:**
```sql
((SELECT auth.uid()) IS NOT NULL)
```

---

### `areas` — `areas_write`

**USING before:**
```sql
check_permission(auth.uid(), 'branches.create'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'branches.create'::text))
```

---

### `audit_logs` — `audit_insert`

**WITH CHECK before:**
```sql
(auth.uid() IS NOT NULL)
```

**WITH CHECK after:**
```sql
((SELECT auth.uid()) IS NOT NULL)
```

---

### `audit_logs` — `audit_select`

**USING before:**
```sql
((user_id = auth.uid()) OR check_permission(auth.uid(), 'settings.audit.read'::text))
```

**USING after:**
```sql
((user_id = (SELECT auth.uid())) OR (SELECT check_permission((SELECT auth.uid()), 'settings.audit.read'::text)))
```

---

### `branches` — `branches_read`

**USING before:**
```sql
check_permission(auth.uid(), 'branches.read'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'branches.read'::text))
```

---

### `branches` — `branches_write`

**USING before:**
```sql
check_permission(auth.uid(), 'branches.create'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'branches.create'::text))
```

---

### `brands` — `brands_read`

**USING before:**
```sql
check_permission(auth.uid(), 'products.read'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'products.read'::text))
```

---

### `brands` — `brands_write`

**USING before:**
```sql
check_permission(auth.uid(), 'products.create'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'products.create'::text))
```

---

### `call_details` — `cd_insert`

**WITH CHECK before:**
```sql
(EXISTS ( SELECT 1
   FROM activities a
  WHERE ((a.id = call_details.activity_id) AND (a.employee_id IN ( SELECT hr_employees.id
           FROM hr_employees
          WHERE (hr_employees.user_id = auth.uid()))) AND check_permission(auth.uid(), 'activities.create'::text))))
```

**WITH CHECK after:**
```sql
(EXISTS ( SELECT 1
   FROM activities a
  WHERE ((a.id = call_details.activity_id) AND (a.employee_id IN ( SELECT hr_employees.id
           FROM hr_employees
          WHERE (hr_employees.user_id = (SELECT auth.uid())))) AND (SELECT check_permission((SELECT auth.uid()), 'activities.create'::text)))))
```

---

### `call_details` — `cd_read`

**USING before:**
```sql
(EXISTS ( SELECT 1
   FROM activities a
  WHERE ((a.id = call_details.activity_id) AND ((a.employee_id IN ( SELECT hr_employees.id
           FROM hr_employees
          WHERE (hr_employees.user_id = auth.uid()))) OR (check_permission(auth.uid(), 'activities.read_team'::text) AND (a.employee_id IN ( SELECT hr_employees.id
           FROM hr_employees
          WHERE (hr_employees.branch_id = ( SELECT hr_employees_1.branch_id
                   FROM hr_employees hr_employees_1
                  WHERE (hr_employees_1.user_id = auth.uid())))))) OR check_permission(auth.uid(), 'activities.read_all'::text)))))
```

**USING after:**
```sql
(EXISTS ( SELECT 1
   FROM activities a
  WHERE ((a.id = call_details.activity_id) AND ((a.employee_id IN ( SELECT hr_employees.id
           FROM hr_employees
          WHERE (hr_employees.user_id = (SELECT auth.uid())))) OR ((SELECT check_permission((SELECT auth.uid()), 'activities.read_team'::text)) AND (a.employee_id IN ( SELECT hr_employees.id
           FROM hr_employees
          WHERE (hr_employees.branch_id = ( SELECT hr_employees_1.branch_id
                   FROM hr_employees hr_employees_1
                  WHERE (hr_employees_1.user_id = (SELECT auth.uid()))))))) OR (SELECT check_permission((SELECT auth.uid()), 'activities.read_all'::text))))))
```

---

### `call_details` — `cd_rls`

**USING before:**
```sql
(activity_id IN ( SELECT activities.id
   FROM activities
  WHERE ((activities.employee_id IN ( SELECT hr_employees.id
           FROM hr_employees
          WHERE (hr_employees.user_id = auth.uid()))) OR check_permission(auth.uid(), 'activities.read_all'::text))))
```

**USING after:**
```sql
(activity_id IN ( SELECT activities.id
   FROM activities
  WHERE ((activities.employee_id IN ( SELECT hr_employees.id
           FROM hr_employees
          WHERE (hr_employees.user_id = (SELECT auth.uid())))) OR (SELECT check_permission((SELECT auth.uid()), 'activities.read_all'::text)))))
```

---

### `call_details` — `cd_update`

**USING before:**
```sql
(EXISTS ( SELECT 1
   FROM activities a
  WHERE ((a.id = call_details.activity_id) AND (((a.employee_id IN ( SELECT hr_employees.id
           FROM hr_employees
          WHERE (hr_employees.user_id = auth.uid()))) AND check_permission(auth.uid(), 'activities.update_own'::text)) OR check_permission(auth.uid(), 'activities.read_all'::text)))))
```

**USING after:**
```sql
(EXISTS ( SELECT 1
   FROM activities a
  WHERE ((a.id = call_details.activity_id) AND (((a.employee_id IN ( SELECT hr_employees.id
           FROM hr_employees
          WHERE (hr_employees.user_id = (SELECT auth.uid())))) AND (SELECT check_permission((SELECT auth.uid()), 'activities.update_own'::text))) OR (SELECT check_permission((SELECT auth.uid()), 'activities.read_all'::text))))))
```

**WITH CHECK before:**
```sql
(EXISTS ( SELECT 1
   FROM activities a
  WHERE ((a.id = call_details.activity_id) AND (((a.employee_id IN ( SELECT hr_employees.id
           FROM hr_employees
          WHERE (hr_employees.user_id = auth.uid()))) AND check_permission(auth.uid(), 'activities.update_own'::text)) OR check_permission(auth.uid(), 'activities.read_all'::text)))))
```

**WITH CHECK after:**
```sql
(EXISTS ( SELECT 1
   FROM activities a
  WHERE ((a.id = call_details.activity_id) AND (((a.employee_id IN ( SELECT hr_employees.id
           FROM hr_employees
          WHERE (hr_employees.user_id = (SELECT auth.uid())))) AND (SELECT check_permission((SELECT auth.uid()), 'activities.update_own'::text))) OR (SELECT check_permission((SELECT auth.uid()), 'activities.read_all'::text))))))
```

---

### `call_plan_items` — `cpi_delete`

**USING before:**
```sql
((check_permission(auth.uid(), 'call_plans.create'::text) AND (EXISTS ( SELECT 1
   FROM call_plans cp
  WHERE ((cp.id = call_plan_items.plan_id) AND (cp.employee_id IN ( SELECT hr_employees.id
           FROM hr_employees
          WHERE (hr_employees.user_id = auth.uid()))))))) OR check_permission(auth.uid(), 'call_plans.read_all'::text))
```

**USING after:**
```sql
(((SELECT check_permission((SELECT auth.uid()), 'call_plans.create'::text)) AND (EXISTS ( SELECT 1
   FROM call_plans cp
  WHERE ((cp.id = call_plan_items.plan_id) AND (cp.employee_id IN ( SELECT hr_employees.id
           FROM hr_employees
          WHERE (hr_employees.user_id = (SELECT auth.uid())))))))) OR (SELECT check_permission((SELECT auth.uid()), 'call_plans.read_all'::text)))
```

---

### `call_plan_items` — `cpi_insert`

**WITH CHECK before:**
```sql
((check_permission(auth.uid(), 'call_plans.create'::text) AND (EXISTS ( SELECT 1
   FROM call_plans cp
  WHERE ((cp.id = call_plan_items.plan_id) AND ((cp.employee_id IN ( SELECT hr_employees.id
           FROM hr_employees
          WHERE (hr_employees.user_id = auth.uid()))) OR check_permission(auth.uid(), 'call_plans.read_team'::text)))))) OR check_permission(auth.uid(), 'call_plans.read_all'::text))
```

**WITH CHECK after:**
```sql
(((SELECT check_permission((SELECT auth.uid()), 'call_plans.create'::text)) AND (EXISTS ( SELECT 1
   FROM call_plans cp
  WHERE ((cp.id = call_plan_items.plan_id) AND ((cp.employee_id IN ( SELECT hr_employees.id
           FROM hr_employees
          WHERE (hr_employees.user_id = (SELECT auth.uid())))) OR (SELECT check_permission((SELECT auth.uid()), 'call_plans.read_team'::text))))))) OR (SELECT check_permission((SELECT auth.uid()), 'call_plans.read_all'::text)))
```

---

### `call_plan_items` — `cpi_read`

**USING before:**
```sql
(EXISTS ( SELECT 1
   FROM call_plans cp
  WHERE ((cp.id = call_plan_items.plan_id) AND ((cp.employee_id IN ( SELECT hr_employees.id
           FROM hr_employees
          WHERE (hr_employees.user_id = auth.uid()))) OR check_permission(auth.uid(), 'call_plans.read_all'::text)))))
```

**USING after:**
```sql
(EXISTS ( SELECT 1
   FROM call_plans cp
  WHERE ((cp.id = call_plan_items.plan_id) AND ((cp.employee_id IN ( SELECT hr_employees.id
           FROM hr_employees
          WHERE (hr_employees.user_id = (SELECT auth.uid())))) OR (SELECT check_permission((SELECT auth.uid()), 'call_plans.read_all'::text))))))
```

---

### `call_plan_items` — `cpi_update`

**USING before:**
```sql
((check_permission(auth.uid(), 'activities.create'::text) AND (EXISTS ( SELECT 1
   FROM call_plans cp
  WHERE ((cp.id = call_plan_items.plan_id) AND (cp.employee_id IN ( SELECT hr_employees.id
           FROM hr_employees
          WHERE (hr_employees.user_id = auth.uid()))))))) OR (check_permission(auth.uid(), 'call_plans.create'::text) AND (EXISTS ( SELECT 1
   FROM call_plans cp
  WHERE ((cp.id = call_plan_items.plan_id) AND (cp.employee_id IN ( SELECT hr_employees.id
           FROM hr_employees
          WHERE (hr_employees.user_id = auth.uid()))))))) OR (check_permission(auth.uid(), 'call_plans.confirm'::text) AND (EXISTS ( SELECT 1
   FROM call_plans cp
  WHERE ((cp.id = call_plan_items.plan_id) AND (cp.employee_id IN ( SELECT hr_employees.id
           FROM hr_employees
          WHERE (hr_employees.branch_id = ( SELECT hr_employees_1.branch_id
                   FROM hr_employees hr_employees_1
                  WHERE (hr_employees_1.user_id = auth.uid())
                 LIMIT 1)))))))) OR check_permission(auth.uid(), 'call_plans.read_all'::text))
```

**USING after:**
```sql
(((SELECT check_permission((SELECT auth.uid()), 'activities.create'::text)) AND (EXISTS ( SELECT 1
   FROM call_plans cp
  WHERE ((cp.id = call_plan_items.plan_id) AND (cp.employee_id IN ( SELECT hr_employees.id
           FROM hr_employees
          WHERE (hr_employees.user_id = (SELECT auth.uid())))))))) OR ((SELECT check_permission((SELECT auth.uid()), 'call_plans.create'::text)) AND (EXISTS ( SELECT 1
   FROM call_plans cp
  WHERE ((cp.id = call_plan_items.plan_id) AND (cp.employee_id IN ( SELECT hr_employees.id
           FROM hr_employees
          WHERE (hr_employees.user_id = (SELECT auth.uid())))))))) OR ((SELECT check_permission((SELECT auth.uid()), 'call_plans.confirm'::text)) AND (EXISTS ( SELECT 1
   FROM call_plans cp
  WHERE ((cp.id = call_plan_items.plan_id) AND (cp.employee_id IN ( SELECT hr_employees.id
           FROM hr_employees
          WHERE (hr_employees.branch_id = ( SELECT hr_employees_1.branch_id
                   FROM hr_employees hr_employees_1
                  WHERE (hr_employees_1.user_id = (SELECT auth.uid()))
                 LIMIT 1)))))))) OR (SELECT check_permission((SELECT auth.uid()), 'call_plans.read_all'::text)))
```

---

### `call_plan_templates` — `cpt_insert`

**WITH CHECK before:**
```sql
(check_permission(auth.uid(), 'call_plans.create'::text) AND ((branch_id IS NULL) OR (branch_id IN ( SELECT hr_employees.branch_id
   FROM hr_employees
  WHERE (hr_employees.user_id = auth.uid()))) OR check_permission(auth.uid(), 'call_plans.read_all'::text)))
```

**WITH CHECK after:**
```sql
((SELECT check_permission((SELECT auth.uid()), 'call_plans.create'::text)) AND ((branch_id IS NULL) OR (branch_id IN ( SELECT hr_employees.branch_id
   FROM hr_employees
  WHERE (hr_employees.user_id = (SELECT auth.uid())))) OR (SELECT check_permission((SELECT auth.uid()), 'call_plans.read_all'::text))))
```

---

### `call_plan_templates` — `cpt_read`

**USING before:**
```sql
(auth.uid() IS NOT NULL)
```

**USING after:**
```sql
((SELECT auth.uid()) IS NOT NULL)
```

---

### `call_plan_templates` — `cpt_update`

**USING before:**
```sql
((check_permission(auth.uid(), 'call_plans.create'::text) AND ((created_by = auth.uid()) OR (employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.branch_id = ( SELECT hr_employees_1.branch_id
           FROM hr_employees hr_employees_1
          WHERE (hr_employees_1.user_id = auth.uid()))))) OR (branch_id IN ( SELECT hr_employees.branch_id
   FROM hr_employees
  WHERE (hr_employees.user_id = auth.uid()))))) OR check_permission(auth.uid(), 'call_plans.read_all'::text))
```

**USING after:**
```sql
(((SELECT check_permission((SELECT auth.uid()), 'call_plans.create'::text)) AND ((created_by = (SELECT auth.uid())) OR (employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.branch_id = ( SELECT hr_employees_1.branch_id
           FROM hr_employees hr_employees_1
          WHERE (hr_employees_1.user_id = (SELECT auth.uid())))))) OR (branch_id IN ( SELECT hr_employees.branch_id
   FROM hr_employees
  WHERE (hr_employees.user_id = (SELECT auth.uid())))))) OR (SELECT check_permission((SELECT auth.uid()), 'call_plans.read_all'::text)))
```

**WITH CHECK before:**
```sql
((check_permission(auth.uid(), 'call_plans.create'::text) AND ((created_by = auth.uid()) OR (employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.branch_id = ( SELECT hr_employees_1.branch_id
           FROM hr_employees hr_employees_1
          WHERE (hr_employees_1.user_id = auth.uid()))))) OR (branch_id IN ( SELECT hr_employees.branch_id
   FROM hr_employees
  WHERE (hr_employees.user_id = auth.uid()))))) OR check_permission(auth.uid(), 'call_plans.read_all'::text))
```

**WITH CHECK after:**
```sql
(((SELECT check_permission((SELECT auth.uid()), 'call_plans.create'::text)) AND ((created_by = (SELECT auth.uid())) OR (employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.branch_id = ( SELECT hr_employees_1.branch_id
           FROM hr_employees hr_employees_1
          WHERE (hr_employees_1.user_id = (SELECT auth.uid())))))) OR (branch_id IN ( SELECT hr_employees.branch_id
   FROM hr_employees
  WHERE (hr_employees.user_id = (SELECT auth.uid())))))) OR (SELECT check_permission((SELECT auth.uid()), 'call_plans.read_all'::text)))
```

---

### `call_plan_templates` — `cpt_write`

**USING before:**
```sql
check_permission(auth.uid(), 'call_plans.create'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'call_plans.create'::text))
```

---

### `call_plans` — `cp_insert`

**WITH CHECK before:**
```sql
(check_permission(auth.uid(), 'call_plans.create'::text) AND ((employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.user_id = auth.uid()))) OR (check_permission(auth.uid(), 'call_plans.read_team'::text) AND (employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.branch_id = ( SELECT hr_employees_1.branch_id
           FROM hr_employees hr_employees_1
          WHERE (hr_employees_1.user_id = auth.uid())))))) OR check_permission(auth.uid(), 'call_plans.read_all'::text)))
```

**WITH CHECK after:**
```sql
((SELECT check_permission((SELECT auth.uid()), 'call_plans.create'::text)) AND ((employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.user_id = (SELECT auth.uid())))) OR ((SELECT check_permission((SELECT auth.uid()), 'call_plans.read_team'::text)) AND (employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.branch_id = ( SELECT hr_employees_1.branch_id
           FROM hr_employees hr_employees_1
          WHERE (hr_employees_1.user_id = (SELECT auth.uid()))))))) OR (SELECT check_permission((SELECT auth.uid()), 'call_plans.read_all'::text))))
```

---

### `call_plans` — `cp_read`

**USING before:**
```sql
((employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.user_id = auth.uid()))) OR (check_permission(auth.uid(), 'call_plans.read_team'::text) AND (employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.branch_id = ( SELECT hr_employees_1.branch_id
           FROM hr_employees hr_employees_1
          WHERE (hr_employees_1.user_id = auth.uid())
         LIMIT 1))))) OR check_permission(auth.uid(), 'call_plans.read_all'::text))
```

**USING after:**
```sql
((employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.user_id = (SELECT auth.uid())))) OR ((SELECT check_permission((SELECT auth.uid()), 'call_plans.read_team'::text)) AND (employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.branch_id = ( SELECT hr_employees_1.branch_id
           FROM hr_employees hr_employees_1
          WHERE (hr_employees_1.user_id = (SELECT auth.uid()))
         LIMIT 1))))) OR (SELECT check_permission((SELECT auth.uid()), 'call_plans.read_all'::text)))
```

---

### `call_plans` — `cp_update`

**USING before:**
```sql
((check_permission(auth.uid(), 'call_plans.create'::text) AND (employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.branch_id = ( SELECT hr_employees_1.branch_id
           FROM hr_employees hr_employees_1
          WHERE (hr_employees_1.user_id = auth.uid())))))) OR (check_permission(auth.uid(), 'call_plans.confirm'::text) AND (employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.branch_id = ( SELECT hr_employees_1.branch_id
           FROM hr_employees hr_employees_1
          WHERE (hr_employees_1.user_id = auth.uid())))))) OR (check_permission(auth.uid(), 'call_plans.cancel'::text) AND (employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.branch_id = ( SELECT hr_employees_1.branch_id
           FROM hr_employees hr_employees_1
          WHERE (hr_employees_1.user_id = auth.uid())))))) OR check_permission(auth.uid(), 'call_plans.read_all'::text))
```

**USING after:**
```sql
(((SELECT check_permission((SELECT auth.uid()), 'call_plans.create'::text)) AND (employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.branch_id = ( SELECT hr_employees_1.branch_id
           FROM hr_employees hr_employees_1
          WHERE (hr_employees_1.user_id = (SELECT auth.uid()))))))) OR ((SELECT check_permission((SELECT auth.uid()), 'call_plans.confirm'::text)) AND (employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.branch_id = ( SELECT hr_employees_1.branch_id
           FROM hr_employees hr_employees_1
          WHERE (hr_employees_1.user_id = (SELECT auth.uid()))))))) OR ((SELECT check_permission((SELECT auth.uid()), 'call_plans.cancel'::text)) AND (employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.branch_id = ( SELECT hr_employees_1.branch_id
           FROM hr_employees hr_employees_1
          WHERE (hr_employees_1.user_id = (SELECT auth.uid()))))))) OR (SELECT check_permission((SELECT auth.uid()), 'call_plans.read_all'::text)))
```

**WITH CHECK before:**
```sql
((check_permission(auth.uid(), 'call_plans.create'::text) AND (employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.branch_id = ( SELECT hr_employees_1.branch_id
           FROM hr_employees hr_employees_1
          WHERE (hr_employees_1.user_id = auth.uid())))))) OR (check_permission(auth.uid(), 'call_plans.confirm'::text) AND (employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.branch_id = ( SELECT hr_employees_1.branch_id
           FROM hr_employees hr_employees_1
          WHERE (hr_employees_1.user_id = auth.uid())))))) OR (check_permission(auth.uid(), 'call_plans.cancel'::text) AND (employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.branch_id = ( SELECT hr_employees_1.branch_id
           FROM hr_employees hr_employees_1
          WHERE (hr_employees_1.user_id = auth.uid())))))) OR check_permission(auth.uid(), 'call_plans.read_all'::text))
```

**WITH CHECK after:**
```sql
(((SELECT check_permission((SELECT auth.uid()), 'call_plans.create'::text)) AND (employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.branch_id = ( SELECT hr_employees_1.branch_id
           FROM hr_employees hr_employees_1
          WHERE (hr_employees_1.user_id = (SELECT auth.uid()))))))) OR ((SELECT check_permission((SELECT auth.uid()), 'call_plans.confirm'::text)) AND (employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.branch_id = ( SELECT hr_employees_1.branch_id
           FROM hr_employees hr_employees_1
          WHERE (hr_employees_1.user_id = (SELECT auth.uid()))))))) OR ((SELECT check_permission((SELECT auth.uid()), 'call_plans.cancel'::text)) AND (employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.branch_id = ( SELECT hr_employees_1.branch_id
           FROM hr_employees hr_employees_1
          WHERE (hr_employees_1.user_id = (SELECT auth.uid()))))))) OR (SELECT check_permission((SELECT auth.uid()), 'call_plans.read_all'::text)))
```

---

### `call_plans` — `cp_write`

**USING before:**
```sql
check_permission(auth.uid(), 'call_plans.create'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'call_plans.create'::text))
```

---

### `chart_of_accounts` — `coa_read`

**USING before:**
```sql
(auth.uid() IS NOT NULL)
```

**USING after:**
```sql
((SELECT auth.uid()) IS NOT NULL)
```

---

### `chart_of_accounts` — `coa_write`

**USING before:**
```sql
check_permission(auth.uid(), 'finance.journal.create'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'finance.journal.create'::text))
```

---

### `cities` — `cities_read`

**USING before:**
```sql
(auth.uid() IS NOT NULL)
```

**USING after:**
```sql
((SELECT auth.uid()) IS NOT NULL)
```

---

### `company_settings` — `settings_select`

**USING before:**
```sql
((is_public = true) OR check_permission(auth.uid(), 'settings.read'::text))
```

**USING after:**
```sql
((is_public = true) OR (SELECT check_permission((SELECT auth.uid()), 'settings.read'::text)))
```

---

### `company_settings` — `settings_update`

**USING before:**
```sql
check_permission(auth.uid(), 'settings.update'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'settings.update'::text))
```

---

### `custody_accounts` — `custody_read`

**USING before:**
```sql
((employee_id = auth.uid()) OR check_permission(auth.uid(), 'finance.custody.read_all'::text))
```

**USING after:**
```sql
((employee_id = (SELECT auth.uid())) OR (SELECT check_permission((SELECT auth.uid()), 'finance.custody.read_all'::text)))
```

---

### `custody_accounts` — `custody_write`

**USING before:**
```sql
check_permission(auth.uid(), 'finance.custody.create'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'finance.custody.create'::text))
```

---

### `custody_transactions` — `custody_txn_read`

**USING before:**
```sql
(check_permission(auth.uid(), 'finance.custody.read_all'::text) OR (custody_id IN ( SELECT custody_accounts.id
   FROM custody_accounts
  WHERE (custody_accounts.employee_id = auth.uid()))))
```

**USING after:**
```sql
((SELECT check_permission((SELECT auth.uid()), 'finance.custody.read_all'::text)) OR (custody_id IN ( SELECT custody_accounts.id
   FROM custody_accounts
  WHERE (custody_accounts.employee_id = (SELECT auth.uid())))))
```

---

### `custody_transactions` — `custody_txn_write`

**USING before:**
```sql
check_permission(auth.uid(), 'finance.custody.transact'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'finance.custody.transact'::text))
```

---

### `customer_branches` — `customer_branches_delete`

**USING before:**
```sql
check_permission(auth.uid(), 'customers.update'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'customers.update'::text))
```

---

### `customer_branches` — `customer_branches_insert`

**WITH CHECK before:**
```sql
(check_permission(auth.uid(), 'customers.create'::text) OR check_permission(auth.uid(), 'customers.update'::text))
```

**WITH CHECK after:**
```sql
((SELECT check_permission((SELECT auth.uid()), 'customers.create'::text)) OR (SELECT check_permission((SELECT auth.uid()), 'customers.update'::text)))
```

---

### `customer_branches` — `customer_branches_modify`

**USING before:**
```sql
check_permission(auth.uid(), 'customers.update'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'customers.update'::text))
```

---

### `customer_branches` — `customer_branches_read`

**USING before:**
```sql
(check_permission(auth.uid(), 'customers.read_all'::text) OR (check_permission(auth.uid(), 'customers.read'::text) AND (customer_id IN ( SELECT customers.id
   FROM customers
  WHERE (customers.assigned_rep_id = auth.uid())))))
```

**USING after:**
```sql
((SELECT check_permission((SELECT auth.uid()), 'customers.read_all'::text)) OR ((SELECT check_permission((SELECT auth.uid()), 'customers.read'::text)) AND (customer_id IN ( SELECT customers.id
   FROM customers
  WHERE (customers.assigned_rep_id = (SELECT auth.uid()))))))
```

---

### `customer_contacts` — `customer_contacts_read`

**USING before:**
```sql
(check_permission(auth.uid(), 'customers.read_all'::text) OR (check_permission(auth.uid(), 'customers.read'::text) AND (customer_id IN ( SELECT customers.id
   FROM customers
  WHERE (customers.assigned_rep_id = auth.uid())))))
```

**USING after:**
```sql
((SELECT check_permission((SELECT auth.uid()), 'customers.read_all'::text)) OR ((SELECT check_permission((SELECT auth.uid()), 'customers.read'::text)) AND (customer_id IN ( SELECT customers.id
   FROM customers
  WHERE (customers.assigned_rep_id = (SELECT auth.uid()))))))
```

---

### `customer_contacts` — `customer_contacts_write`

**USING before:**
```sql
check_permission(auth.uid(), 'customers.update'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'customers.update'::text))
```

---

### `customer_credit_history` — `credit_history_read`

**USING before:**
```sql
check_permission(auth.uid(), 'customers.read'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'customers.read'::text))
```

---

### `customer_ledger` — `cust_ledger_read`

**USING before:**
```sql
check_permission(auth.uid(), 'finance.ledger.read'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'finance.ledger.read'::text))
```

---

### `customer_ledger` — `cust_ledger_write`

**USING before:**
```sql
check_permission(auth.uid(), 'finance.ledger.adjust'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'finance.ledger.adjust'::text))
```

---

### `customers` — `customers_delete`

**USING before:**
```sql
check_permission(auth.uid(), 'customers.delete'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'customers.delete'::text))
```

---

### `customers` — `customers_read`

**USING before:**
```sql
(check_permission(auth.uid(), 'customers.read_all'::text) OR (check_permission(auth.uid(), 'customers.read'::text) AND (assigned_rep_id = auth.uid())))
```

**USING after:**
```sql
((SELECT check_permission((SELECT auth.uid()), 'customers.read_all'::text)) OR ((SELECT check_permission((SELECT auth.uid()), 'customers.read'::text)) AND (assigned_rep_id = (SELECT auth.uid()))))
```

---

### `customers` — `customers_update`

**USING before:**
```sql
check_permission(auth.uid(), 'customers.update'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'customers.update'::text))
```

---

### `customers` — `customers_write`

**WITH CHECK before:**
```sql
check_permission(auth.uid(), 'customers.create'::text)
```

**WITH CHECK after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'customers.create'::text))
```

---

### `expense_categories` — `exp_cat_read`

**USING before:**
```sql
(auth.uid() IS NOT NULL)
```

**USING after:**
```sql
((SELECT auth.uid()) IS NOT NULL)
```

---

### `expense_categories` — `exp_cat_write`

**USING before:**
```sql
check_permission(auth.uid(), 'finance.expenses.approve'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'finance.expenses.approve'::text))
```

---

### `expenses` — `expenses_insert`

**WITH CHECK before:**
```sql
check_permission(auth.uid(), 'finance.expenses.create'::text)
```

**WITH CHECK after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'finance.expenses.create'::text))
```

---

### `expenses` — `expenses_read`

**USING before:**
```sql
((created_by = auth.uid()) OR check_permission(auth.uid(), 'finance.expenses.read_all'::text))
```

**USING after:**
```sql
((created_by = (SELECT auth.uid())) OR (SELECT check_permission((SELECT auth.uid()), 'finance.expenses.read_all'::text)))
```

---

### `expenses` — `expenses_update`

**USING before:**
```sql
(((created_by = auth.uid()) AND (status = 'draft'::text)) OR check_permission(auth.uid(), 'finance.expenses.approve'::text))
```

**USING after:**
```sql
(((created_by = (SELECT auth.uid())) AND (status = 'draft'::text)) OR (SELECT check_permission((SELECT auth.uid()), 'finance.expenses.approve'::text)))
```

**WITH CHECK before:**
```sql
(check_permission(auth.uid(), 'finance.expenses.approve'::text) OR (status = ANY (ARRAY['draft'::text, 'pending_approval'::text])))
```

**WITH CHECK after:**
```sql
((SELECT check_permission((SELECT auth.uid()), 'finance.expenses.approve'::text)) OR (status = ANY (ARRAY['draft'::text, 'pending_approval'::text])))
```

---

### `feature_flags` — `flags_select`

**USING before:**
```sql
(auth.uid() IS NOT NULL)
```

**USING after:**
```sql
((SELECT auth.uid()) IS NOT NULL)
```

---

### `feature_flags` — `flags_write`

**USING before:**
```sql
check_permission(auth.uid(), 'settings.update'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'settings.update'::text))
```

---

### `governorates` — `geo_read`

**USING before:**
```sql
(auth.uid() IS NOT NULL)
```

**USING after:**
```sql
((SELECT auth.uid()) IS NOT NULL)
```

---

### `hr_advance_installments` — `hr_inst_read`

**USING before:**
```sql
((advance_id IN ( SELECT hr_advances.id
   FROM hr_advances
  WHERE (hr_advances.employee_id IN ( SELECT hr_employees.id
           FROM hr_employees
          WHERE (hr_employees.user_id = auth.uid()))))) OR check_permission(auth.uid(), 'hr.advances.read'::text))
```

**USING after:**
```sql
((advance_id IN ( SELECT hr_advances.id
   FROM hr_advances
  WHERE (hr_advances.employee_id IN ( SELECT hr_employees.id
           FROM hr_employees
          WHERE (hr_employees.user_id = (SELECT auth.uid())))))) OR (SELECT check_permission((SELECT auth.uid()), 'hr.advances.read'::text)))
```

---

### `hr_advance_installments` — `hr_inst_write`

**USING before:**
```sql
check_permission(auth.uid(), 'hr.payroll.calculate'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'hr.payroll.calculate'::text))
```

---

### `hr_advances` — `hr_adv_insert`

**WITH CHECK before:**
```sql
((employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.user_id = auth.uid()))) OR check_permission(auth.uid(), 'hr.advances.create'::text))
```

**WITH CHECK after:**
```sql
((employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.user_id = (SELECT auth.uid())))) OR (SELECT check_permission((SELECT auth.uid()), 'hr.advances.create'::text)))
```

---

### `hr_advances` — `hr_adv_read`

**USING before:**
```sql
((employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.user_id = auth.uid()))) OR check_permission(auth.uid(), 'hr.advances.read'::text))
```

**USING after:**
```sql
((employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.user_id = (SELECT auth.uid())))) OR (SELECT check_permission((SELECT auth.uid()), 'hr.advances.read'::text)))
```

---

### `hr_advances` — `hr_adv_update`

**USING before:**
```sql
check_permission(auth.uid(), 'hr.advances.approve'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'hr.advances.approve'::text))
```

---

### `hr_attendance_alerts` — `hr_attendance_alerts_select`

**USING before:**
```sql
((employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.user_id = auth.uid()))) OR check_permission(auth.uid(), 'hr.attendance.read'::text) OR check_permission(auth.uid(), 'hr.payroll.read'::text) OR check_permission(auth.uid(), 'hr.permissions.approve'::text))
```

**USING after:**
```sql
((employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.user_id = (SELECT auth.uid())))) OR (SELECT check_permission((SELECT auth.uid()), 'hr.attendance.read'::text)) OR (SELECT check_permission((SELECT auth.uid()), 'hr.payroll.read'::text)) OR (SELECT check_permission((SELECT auth.uid()), 'hr.permissions.approve'::text)))
```

---

### `hr_attendance_alerts` — `hr_attendance_alerts_update`

**USING before:**
```sql
(check_permission(auth.uid(), 'hr.attendance.edit'::text) OR check_permission(auth.uid(), 'hr.permissions.approve'::text) OR check_permission(auth.uid(), 'hr.payroll.approve'::text))
```

**USING after:**
```sql
((SELECT check_permission((SELECT auth.uid()), 'hr.attendance.edit'::text)) OR (SELECT check_permission((SELECT auth.uid()), 'hr.permissions.approve'::text)) OR (SELECT check_permission((SELECT auth.uid()), 'hr.payroll.approve'::text)))
```

**WITH CHECK before:**
```sql
(check_permission(auth.uid(), 'hr.attendance.edit'::text) OR check_permission(auth.uid(), 'hr.permissions.approve'::text) OR check_permission(auth.uid(), 'hr.payroll.approve'::text))
```

**WITH CHECK after:**
```sql
((SELECT check_permission((SELECT auth.uid()), 'hr.attendance.edit'::text)) OR (SELECT check_permission((SELECT auth.uid()), 'hr.permissions.approve'::text)) OR (SELECT check_permission((SELECT auth.uid()), 'hr.payroll.approve'::text)))
```

---

### `hr_attendance_days` — `hr_att_read`

**USING before:**
```sql
((employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.user_id = auth.uid()))) OR check_permission(auth.uid(), 'hr.attendance.read'::text))
```

**USING after:**
```sql
((employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.user_id = (SELECT auth.uid())))) OR (SELECT check_permission((SELECT auth.uid()), 'hr.attendance.read'::text)))
```

---

### `hr_attendance_days` — `hr_att_write`

**USING before:**
```sql
check_permission(auth.uid(), 'hr.attendance.create'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'hr.attendance.create'::text))
```

---

### `hr_attendance_logs` — `hr_logs_insert`

**WITH CHECK before:**
```sql
(auth.uid() IS NOT NULL)
```

**WITH CHECK after:**
```sql
((SELECT auth.uid()) IS NOT NULL)
```

---

### `hr_attendance_logs` — `hr_logs_read`

**USING before:**
```sql
((employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.user_id = auth.uid()))) OR check_permission(auth.uid(), 'hr.attendance.read'::text))
```

**USING after:**
```sql
((employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.user_id = (SELECT auth.uid())))) OR (SELECT check_permission((SELECT auth.uid()), 'hr.attendance.read'::text)))
```

---

### `hr_commission_records` — `hr_cr_read`

**USING before:**
```sql
((employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.user_id = auth.uid()))) OR check_permission(auth.uid(), 'hr.payroll.read'::text))
```

**USING after:**
```sql
((employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.user_id = (SELECT auth.uid())))) OR (SELECT check_permission((SELECT auth.uid()), 'hr.payroll.read'::text)))
```

---

### `hr_commission_records` — `hr_cr_write`

**USING before:**
```sql
check_permission(auth.uid(), 'hr.payroll.calculate'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'hr.payroll.calculate'::text))
```

---

### `hr_commission_targets` — `hr_ct_read`

**USING before:**
```sql
((employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.user_id = auth.uid()))) OR check_permission(auth.uid(), 'hr.payroll.read'::text))
```

**USING after:**
```sql
((employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.user_id = (SELECT auth.uid())))) OR (SELECT check_permission((SELECT auth.uid()), 'hr.payroll.read'::text)))
```

---

### `hr_commission_targets` — `hr_ct_write`

**USING before:**
```sql
check_permission(auth.uid(), 'hr.payroll.calculate'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'hr.payroll.calculate'::text))
```

---

### `hr_contracts` — `hr_contracts_read`

**USING before:**
```sql
((employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.user_id = auth.uid()))) OR check_permission(auth.uid(), 'hr.employees.read'::text))
```

**USING after:**
```sql
((employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.user_id = (SELECT auth.uid())))) OR (SELECT check_permission((SELECT auth.uid()), 'hr.employees.read'::text)))
```

---

### `hr_contracts` — `hr_contracts_write`

**USING before:**
```sql
check_permission(auth.uid(), 'hr.employees.create'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'hr.employees.create'::text))
```

---

### `hr_delegations` — `hr_deleg_read`

**USING before:**
```sql
((delegator_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.user_id = auth.uid()))) OR (delegate_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.user_id = auth.uid()))) OR check_permission(auth.uid(), 'hr.employees.read'::text))
```

**USING after:**
```sql
((delegator_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.user_id = (SELECT auth.uid())))) OR (delegate_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.user_id = (SELECT auth.uid())))) OR (SELECT check_permission((SELECT auth.uid()), 'hr.employees.read'::text)))
```

---

### `hr_delegations` — `hr_deleg_write`

**USING before:**
```sql
check_permission(auth.uid(), 'hr.employees.create'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'hr.employees.create'::text))
```

---

### `hr_departments` — `hr_depts_read`

**USING before:**
```sql
(auth.uid() IS NOT NULL)
```

**USING after:**
```sql
((SELECT auth.uid()) IS NOT NULL)
```

---

### `hr_departments` — `hr_depts_write`

**USING before:**
```sql
check_permission(auth.uid(), 'hr.employees.create'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'hr.employees.create'::text))
```

---

### `hr_employee_documents` — `hr_docs_rls_read`

**USING before:**
```sql
((employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.user_id = auth.uid()))) OR check_permission(auth.uid(), 'hr.employees.read'::text))
```

**USING after:**
```sql
((employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.user_id = (SELECT auth.uid())))) OR (SELECT check_permission((SELECT auth.uid()), 'hr.employees.read'::text)))
```

---

### `hr_employee_documents` — `hr_docs_rls_write`

**USING before:**
```sql
check_permission(auth.uid(), 'hr.employees.create'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'hr.employees.create'::text))
```

---

### `hr_employees` — `hr_emp_insert`

**WITH CHECK before:**
```sql
check_permission(auth.uid(), 'hr.employees.create'::text)
```

**WITH CHECK after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'hr.employees.create'::text))
```

---

### `hr_employees` — `hr_emp_read`

**USING before:**
```sql
((user_id = auth.uid()) OR check_permission(auth.uid(), 'hr.employees.read'::text))
```

**USING after:**
```sql
((user_id = (SELECT auth.uid())) OR (SELECT check_permission((SELECT auth.uid()), 'hr.employees.read'::text)))
```

---

### `hr_employees` — `hr_emp_update`

**USING before:**
```sql
check_permission(auth.uid(), 'hr.employees.create'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'hr.employees.create'::text))
```

---

### `hr_leave_balances` — `hr_lb_read`

**USING before:**
```sql
((employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.user_id = auth.uid()))) OR check_permission(auth.uid(), 'hr.leaves.read'::text))
```

**USING after:**
```sql
((employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.user_id = (SELECT auth.uid())))) OR (SELECT check_permission((SELECT auth.uid()), 'hr.leaves.read'::text)))
```

---

### `hr_leave_balances` — `hr_lb_write`

**USING before:**
```sql
check_permission(auth.uid(), 'hr.payroll.calculate'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'hr.payroll.calculate'::text))
```

---

### `hr_leave_requests` — `hr_lr_insert`

**WITH CHECK before:**
```sql
((employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.user_id = auth.uid()))) OR check_permission(auth.uid(), 'hr.leaves.create'::text))
```

**WITH CHECK after:**
```sql
((employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.user_id = (SELECT auth.uid())))) OR (SELECT check_permission((SELECT auth.uid()), 'hr.leaves.create'::text)))
```

---

### `hr_leave_requests` — `hr_lr_read`

**USING before:**
```sql
((employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.user_id = auth.uid()))) OR (supervisor_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.user_id = auth.uid()))) OR check_permission(auth.uid(), 'hr.leaves.read'::text))
```

**USING after:**
```sql
((employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.user_id = (SELECT auth.uid())))) OR (supervisor_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.user_id = (SELECT auth.uid())))) OR (SELECT check_permission((SELECT auth.uid()), 'hr.leaves.read'::text)))
```

---

### `hr_leave_requests` — `hr_lr_update`

**USING before:**
```sql
(((employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.user_id = auth.uid()))) AND (status = 'pending_supervisor'::hr_leave_request_status)) OR check_permission(auth.uid(), 'hr.leaves.approve'::text))
```

**USING after:**
```sql
(((employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.user_id = (SELECT auth.uid())))) AND (status = 'pending_supervisor'::hr_leave_request_status)) OR (SELECT check_permission((SELECT auth.uid()), 'hr.leaves.approve'::text)))
```

---

### `hr_leave_types` — `hr_lt_read`

**USING before:**
```sql
(auth.uid() IS NOT NULL)
```

**USING after:**
```sql
((SELECT auth.uid()) IS NOT NULL)
```

---

### `hr_leave_types` — `hr_lt_write`

**USING before:**
```sql
check_permission(auth.uid(), 'hr.settings.update'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'hr.settings.update'::text))
```

---

### `hr_payroll_adjustments` — `adj_insert`

**WITH CHECK before:**
```sql
check_permission(auth.uid(), 'hr.adjustments.create'::text)
```

**WITH CHECK after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'hr.adjustments.create'::text))
```

---

### `hr_payroll_adjustments` — `adj_select`

**USING before:**
```sql
(check_permission(auth.uid(), 'hr.payroll.read'::text) OR check_permission(auth.uid(), 'hr.adjustments.read'::text))
```

**USING after:**
```sql
((SELECT check_permission((SELECT auth.uid()), 'hr.payroll.read'::text)) OR (SELECT check_permission((SELECT auth.uid()), 'hr.adjustments.read'::text)))
```

---

### `hr_payroll_adjustments` — `adj_update`

**USING before:**
```sql
(check_permission(auth.uid(), 'hr.adjustments.approve'::text) OR ((created_by = auth.uid()) AND (status = 'pending'::text)))
```

**USING after:**
```sql
((SELECT check_permission((SELECT auth.uid()), 'hr.adjustments.approve'::text)) OR ((created_by = (SELECT auth.uid())) AND (status = 'pending'::text)))
```

---

### `hr_payroll_lines` — `hr_pl_read`

**USING before:**
```sql
((employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.user_id = auth.uid()))) OR check_permission(auth.uid(), 'hr.payroll.read'::text))
```

**USING after:**
```sql
((employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.user_id = (SELECT auth.uid())))) OR (SELECT check_permission((SELECT auth.uid()), 'hr.payroll.read'::text)))
```

---

### `hr_payroll_lines` — `hr_pl_write`

**USING before:**
```sql
check_permission(auth.uid(), 'hr.payroll.calculate'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'hr.payroll.calculate'::text))
```

---

### `hr_payroll_periods` — `hr_pp_read`

**USING before:**
```sql
(auth.uid() IS NOT NULL)
```

**USING after:**
```sql
((SELECT auth.uid()) IS NOT NULL)
```

---

### `hr_payroll_periods` — `hr_pp_write`

**USING before:**
```sql
check_permission(auth.uid(), 'hr.payroll.calculate'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'hr.payroll.calculate'::text))
```

---

### `hr_payroll_runs` — `hr_pr_read`

**USING before:**
```sql
check_permission(auth.uid(), 'hr.payroll.read'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'hr.payroll.read'::text))
```

---

### `hr_payroll_runs` — `hr_pr_write`

**USING before:**
```sql
check_permission(auth.uid(), 'hr.payroll.calculate'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'hr.payroll.calculate'::text))
```

---

### `hr_penalty_instances` — `hr_pen_inst_read`

**USING before:**
```sql
((employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.user_id = auth.uid()))) OR check_permission(auth.uid(), 'hr.attendance.read'::text))
```

**USING after:**
```sql
((employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.user_id = (SELECT auth.uid())))) OR (SELECT check_permission((SELECT auth.uid()), 'hr.attendance.read'::text)))
```

---

### `hr_penalty_instances` — `hr_pen_inst_write`

**USING before:**
```sql
check_permission(auth.uid(), 'hr.attendance.approve'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'hr.attendance.approve'::text))
```

---

### `hr_penalty_rules` — `hr_pen_rules_read`

**USING before:**
```sql
(auth.uid() IS NOT NULL)
```

**USING after:**
```sql
((SELECT auth.uid()) IS NOT NULL)
```

---

### `hr_penalty_rules` — `hr_pen_rules_write`

**USING before:**
```sql
check_permission(auth.uid(), 'hr.settings.update'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'hr.settings.update'::text))
```

---

### `hr_permission_requests` — `hr_perm_insert`

**WITH CHECK before:**
```sql
((employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.user_id = auth.uid()))) OR check_permission(auth.uid(), 'hr.attendance.create'::text))
```

**WITH CHECK after:**
```sql
((employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.user_id = (SELECT auth.uid())))) OR (SELECT check_permission((SELECT auth.uid()), 'hr.attendance.create'::text)))
```

---

### `hr_permission_requests` — `hr_perm_read`

**USING before:**
```sql
((employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.user_id = auth.uid()))) OR check_permission(auth.uid(), 'hr.attendance.read'::text))
```

**USING after:**
```sql
((employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.user_id = (SELECT auth.uid())))) OR (SELECT check_permission((SELECT auth.uid()), 'hr.attendance.read'::text)))
```

---

### `hr_permission_requests` — `hr_perm_update`

**USING before:**
```sql
check_permission(auth.uid(), 'hr.attendance.approve'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'hr.attendance.approve'::text))
```

---

### `hr_positions` — `hr_pos_read`

**USING before:**
```sql
(auth.uid() IS NOT NULL)
```

**USING after:**
```sql
((SELECT auth.uid()) IS NOT NULL)
```

---

### `hr_positions` — `hr_pos_write`

**USING before:**
```sql
check_permission(auth.uid(), 'hr.employees.create'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'hr.employees.create'::text))
```

---

### `hr_public_holidays` — `hr_holidays_read`

**USING before:**
```sql
(auth.uid() IS NOT NULL)
```

**USING after:**
```sql
((SELECT auth.uid()) IS NOT NULL)
```

---

### `hr_public_holidays` — `hr_holidays_write`

**USING before:**
```sql
check_permission(auth.uid(), 'hr.settings.update'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'hr.settings.update'::text))
```

---

### `hr_salary_history` — `hr_sal_hist_read`

**USING before:**
```sql
((employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.user_id = auth.uid()))) OR check_permission(auth.uid(), 'hr.payroll.read'::text))
```

**USING after:**
```sql
((employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.user_id = (SELECT auth.uid())))) OR (SELECT check_permission((SELECT auth.uid()), 'hr.payroll.read'::text)))
```

---

### `hr_salary_history` — `hr_sal_hist_write`

**USING before:**
```sql
check_permission(auth.uid(), 'hr.payroll.calculate'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'hr.payroll.calculate'::text))
```

---

### `hr_work_locations` — `hr_locations_read`

**USING before:**
```sql
((auth.uid() IS NOT NULL) AND (is_active = true))
```

**USING after:**
```sql
(((SELECT auth.uid()) IS NOT NULL) AND (is_active = true))
```

---

### `hr_work_locations` — `hr_locations_write`

**USING before:**
```sql
check_permission(auth.uid(), 'hr.employees.create'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'hr.employees.create'::text))
```

---

### `journal_entries` — `je_read`

**USING before:**
```sql
check_permission(auth.uid(), 'finance.journal.read'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'finance.journal.read'::text))
```

---

### `journal_entries` — `je_write`

**USING before:**
```sql
check_permission(auth.uid(), 'finance.journal.create'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'finance.journal.create'::text))
```

---

### `journal_entry_lines` — `je_lines_read`

**USING before:**
```sql
check_permission(auth.uid(), 'finance.journal.read'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'finance.journal.read'::text))
```

---

### `journal_entry_lines` — `je_lines_write`

**USING before:**
```sql
check_permission(auth.uid(), 'finance.journal.create'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'finance.journal.create'::text))
```

---

### `notification_delivery_log` — `delivery_log_select_own`

**USING before:**
```sql
(notification_id IN ( SELECT notifications.id
   FROM notifications
  WHERE (notifications.user_id = auth.uid())))
```

**USING after:**
```sql
(notification_id IN ( SELECT notifications.id
   FROM notifications
  WHERE (notifications.user_id = (SELECT auth.uid()))))
```

---

### `notification_preferences` — `preferences_select_own`

**USING before:**
```sql
(auth.uid() = user_id)
```

**USING after:**
```sql
((SELECT auth.uid()) = user_id)
```

---

### `notification_preferences` — `preferences_upsert_own`

**USING before:**
```sql
(auth.uid() = user_id)
```

**USING after:**
```sql
((SELECT auth.uid()) = user_id)
```

**WITH CHECK before:**
```sql
(auth.uid() = user_id)
```

**WITH CHECK after:**
```sql
((SELECT auth.uid()) = user_id)
```

---

### `notifications` — `notifications_select_own`

**USING before:**
```sql
(auth.uid() = user_id)
```

**USING after:**
```sql
((SELECT auth.uid()) = user_id)
```

---

### `payment_receipts` — `receipts_insert`

**WITH CHECK before:**
```sql
check_permission(auth.uid(), 'finance.payments.create'::text)
```

**WITH CHECK after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'finance.payments.create'::text))
```

---

### `payment_receipts` — `receipts_read`

**USING before:**
```sql
((created_by = auth.uid()) OR (collected_by = auth.uid()) OR check_permission(auth.uid(), 'finance.payments.read_all'::text))
```

**USING after:**
```sql
((created_by = (SELECT auth.uid())) OR (collected_by = (SELECT auth.uid())) OR (SELECT check_permission((SELECT auth.uid()), 'finance.payments.read_all'::text)))
```

---

### `payment_receipts` — `receipts_update`

**USING before:**
```sql
check_permission(auth.uid(), 'finance.payments.confirm'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'finance.payments.confirm'::text))
```

---

### `price_list_assignments` — `price_list_assignments_read`

**USING before:**
```sql
check_permission(auth.uid(), 'price_lists.read'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'price_lists.read'::text))
```

---

### `price_list_assignments` — `price_list_assignments_write`

**USING before:**
```sql
check_permission(auth.uid(), 'price_lists.update'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'price_lists.update'::text))
```

---

### `price_list_items` — `price_list_items_read`

**USING before:**
```sql
check_permission(auth.uid(), 'price_lists.read'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'price_lists.read'::text))
```

---

### `price_list_items` — `price_list_items_write`

**USING before:**
```sql
check_permission(auth.uid(), 'price_lists.update'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'price_lists.update'::text))
```

---

### `price_lists` — `price_lists_read`

**USING before:**
```sql
check_permission(auth.uid(), 'price_lists.read'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'price_lists.read'::text))
```

---

### `price_lists` — `price_lists_write`

**USING before:**
```sql
check_permission(auth.uid(), 'price_lists.update'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'price_lists.update'::text))
```

---

### `product_bundle_items` — `bundle_items_read`

**USING before:**
```sql
check_permission(auth.uid(), 'products.read'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'products.read'::text))
```

---

### `product_bundle_items` — `bundle_items_write`

**USING before:**
```sql
check_permission(auth.uid(), 'products.create'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'products.create'::text))
```

---

### `product_bundles` — `bundles_read`

**USING before:**
```sql
check_permission(auth.uid(), 'products.read'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'products.read'::text))
```

---

### `product_bundles` — `bundles_write`

**USING before:**
```sql
check_permission(auth.uid(), 'products.create'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'products.create'::text))
```

---

### `product_categories` — `categories_read`

**USING before:**
```sql
check_permission(auth.uid(), 'products.read'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'products.read'::text))
```

---

### `product_categories` — `categories_write`

**USING before:**
```sql
check_permission(auth.uid(), 'categories.create'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'categories.create'::text))
```

---

### `product_units` — `product_units_read`

**USING before:**
```sql
check_permission(auth.uid(), 'products.read'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'products.read'::text))
```

---

### `product_units` — `product_units_write`

**USING before:**
```sql
check_permission(auth.uid(), 'products.create'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'products.create'::text))
```

---

### `products` — `products_read`

**USING before:**
```sql
check_permission(auth.uid(), 'products.read'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'products.read'::text))
```

---

### `products` — `products_write`

**USING before:**
```sql
check_permission(auth.uid(), 'products.create'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'products.create'::text))
```

---

### `profiles` — `profiles_select`

**USING before:**
```sql
((id = auth.uid()) OR check_permission(auth.uid(), 'auth.users.read'::text))
```

**USING after:**
```sql
((id = (SELECT auth.uid())) OR (SELECT check_permission((SELECT auth.uid()), 'auth.users.read'::text)))
```

---

### `profiles` — `profiles_update`

**USING before:**
```sql
((id = auth.uid()) OR check_permission(auth.uid(), 'auth.users.update'::text))
```

**USING after:**
```sql
((id = (SELECT auth.uid())) OR (SELECT check_permission((SELECT auth.uid()), 'auth.users.update'::text)))
```

---

### `purchase_invoice_items` — `pii_insert`

**WITH CHECK before:**
```sql
check_permission(auth.uid(), 'procurement.invoices.create'::text)
```

**WITH CHECK after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'procurement.invoices.create'::text))
```

---

### `purchase_invoice_items` — `pii_read`

**USING before:**
```sql
check_permission(auth.uid(), 'procurement.invoices.read'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'procurement.invoices.read'::text))
```

---

### `purchase_invoice_items` — `pii_update`

**USING before:**
```sql
check_permission(auth.uid(), 'procurement.invoices.receive'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'procurement.invoices.receive'::text))
```

---

### `purchase_invoices` — `pi_insert`

**WITH CHECK before:**
```sql
check_permission(auth.uid(), 'procurement.invoices.create'::text)
```

**WITH CHECK after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'procurement.invoices.create'::text))
```

---

### `purchase_invoices` — `pi_read`

**USING before:**
```sql
check_permission(auth.uid(), 'procurement.invoices.read'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'procurement.invoices.read'::text))
```

---

### `purchase_invoices` — `pi_update`

**USING before:**
```sql
(check_permission(auth.uid(), 'procurement.invoices.receive'::text) OR check_permission(auth.uid(), 'procurement.invoices.bill'::text) OR check_permission(auth.uid(), 'procurement.invoices.pay'::text))
```

**USING after:**
```sql
((SELECT check_permission((SELECT auth.uid()), 'procurement.invoices.receive'::text)) OR (SELECT check_permission((SELECT auth.uid()), 'procurement.invoices.bill'::text)) OR (SELECT check_permission((SELECT auth.uid()), 'procurement.invoices.pay'::text)))
```

---

### `purchase_return_items` — `pri_insert`

**WITH CHECK before:**
```sql
check_permission(auth.uid(), 'procurement.returns.create'::text)
```

**WITH CHECK after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'procurement.returns.create'::text))
```

---

### `purchase_return_items` — `pri_read`

**USING before:**
```sql
check_permission(auth.uid(), 'procurement.returns.read'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'procurement.returns.read'::text))
```

---

### `purchase_return_items` — `pri_update`

**USING before:**
```sql
check_permission(auth.uid(), 'procurement.returns.confirm'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'procurement.returns.confirm'::text))
```

---

### `purchase_returns` — `pr_insert`

**WITH CHECK before:**
```sql
check_permission(auth.uid(), 'procurement.returns.create'::text)
```

**WITH CHECK after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'procurement.returns.create'::text))
```

---

### `purchase_returns` — `pr_read`

**USING before:**
```sql
check_permission(auth.uid(), 'procurement.returns.read'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'procurement.returns.read'::text))
```

---

### `purchase_returns` — `pr_update`

**USING before:**
```sql
(check_permission(auth.uid(), 'procurement.returns.create'::text) OR check_permission(auth.uid(), 'procurement.returns.confirm'::text))
```

**USING after:**
```sql
((SELECT check_permission((SELECT auth.uid()), 'procurement.returns.create'::text)) OR (SELECT check_permission((SELECT auth.uid()), 'procurement.returns.confirm'::text)))
```

---

### `push_subscriptions` — `push_delete_own`

**USING before:**
```sql
(auth.uid() = user_id)
```

**USING after:**
```sql
((SELECT auth.uid()) = user_id)
```

---

### `push_subscriptions` — `push_insert_own`

**WITH CHECK before:**
```sql
(auth.uid() = user_id)
```

**WITH CHECK after:**
```sql
((SELECT auth.uid()) = user_id)
```

---

### `push_subscriptions` — `push_select_own`

**USING before:**
```sql
(auth.uid() = user_id)
```

**USING after:**
```sql
((SELECT auth.uid()) = user_id)
```

---

### `push_subscriptions` — `push_update_own`

**USING before:**
```sql
(auth.uid() = user_id)
```

**USING after:**
```sql
((SELECT auth.uid()) = user_id)
```

---

### `role_permissions` — `role_perms_delete`

**USING before:**
```sql
check_permission(auth.uid(), 'auth.roles.update'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'auth.roles.update'::text))
```

---

### `role_permissions` — `role_perms_insert`

**WITH CHECK before:**
```sql
check_permission(auth.uid(), 'auth.roles.update'::text)
```

**WITH CHECK after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'auth.roles.update'::text))
```

---

### `role_permissions` — `role_perms_select`

**USING before:**
```sql
(auth.uid() IS NOT NULL)
```

**USING after:**
```sql
((SELECT auth.uid()) IS NOT NULL)
```

---

### `role_permissions` — `role_perms_update`

**USING before:**
```sql
check_permission(auth.uid(), 'auth.roles.update'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'auth.roles.update'::text))
```

---

### `roles` — `roles_delete`

**USING before:**
```sql
((NOT is_system) AND check_permission(auth.uid(), 'auth.roles.delete'::text))
```

**USING after:**
```sql
((NOT is_system) AND (SELECT check_permission((SELECT auth.uid()), 'auth.roles.delete'::text)))
```

---

### `roles` — `roles_insert`

**WITH CHECK before:**
```sql
check_permission(auth.uid(), 'auth.roles.create'::text)
```

**WITH CHECK after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'auth.roles.create'::text))
```

---

### `roles` — `roles_select`

**USING before:**
```sql
(auth.uid() IS NOT NULL)
```

**USING after:**
```sql
((SELECT auth.uid()) IS NOT NULL)
```

---

### `roles` — `roles_update`

**USING before:**
```sql
((NOT is_system) AND check_permission(auth.uid(), 'auth.roles.update'::text))
```

**USING after:**
```sql
((NOT is_system) AND (SELECT check_permission((SELECT auth.uid()), 'auth.roles.update'::text)))
```

---

### `sales_order_items` — `soi_read`

**USING before:**
```sql
(EXISTS ( SELECT 1
   FROM sales_orders so
  WHERE ((so.id = sales_order_items.order_id) AND ((so.rep_id = auth.uid()) OR (so.created_by_id = auth.uid()) OR check_permission(auth.uid(), 'sales.orders.read_all'::text)))))
```

**USING after:**
```sql
(EXISTS ( SELECT 1
   FROM sales_orders so
  WHERE ((so.id = sales_order_items.order_id) AND ((so.rep_id = (SELECT auth.uid())) OR (so.created_by_id = (SELECT auth.uid())) OR (SELECT check_permission((SELECT auth.uid()), 'sales.orders.read_all'::text))))))
```

---

### `sales_order_items` — `soi_write`

**USING before:**
```sql
(EXISTS ( SELECT 1
   FROM sales_orders so
  WHERE (((so.id = sales_order_items.order_id) AND ((so.status = 'draft'::sales_order_status) AND ((so.rep_id = auth.uid()) OR (so.created_by_id = auth.uid())))) OR check_permission(auth.uid(), 'sales.orders.read_all'::text))))
```

**USING after:**
```sql
(EXISTS ( SELECT 1
   FROM sales_orders so
  WHERE (((so.id = sales_order_items.order_id) AND ((so.status = 'draft'::sales_order_status) AND ((so.rep_id = (SELECT auth.uid())) OR (so.created_by_id = (SELECT auth.uid()))))) OR (SELECT check_permission((SELECT auth.uid()), 'sales.orders.read_all'::text)))))
```

---

### `sales_orders` — `so_insert`

**WITH CHECK before:**
```sql
check_permission(auth.uid(), 'sales.orders.create'::text)
```

**WITH CHECK after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'sales.orders.create'::text))
```

---

### `sales_orders` — `so_read`

**USING before:**
```sql
((rep_id = auth.uid()) OR (created_by_id = auth.uid()) OR check_permission(auth.uid(), 'sales.orders.read_all'::text))
```

**USING after:**
```sql
((rep_id = (SELECT auth.uid())) OR (created_by_id = (SELECT auth.uid())) OR (SELECT check_permission((SELECT auth.uid()), 'sales.orders.read_all'::text)))
```

---

### `sales_orders` — `so_update`

**USING before:**
```sql
(((status = 'draft'::sales_order_status) AND ((rep_id = auth.uid()) OR (created_by_id = auth.uid()))) OR check_permission(auth.uid(), 'sales.orders.read_all'::text))
```

**USING after:**
```sql
(((status = 'draft'::sales_order_status) AND ((rep_id = (SELECT auth.uid())) OR (created_by_id = (SELECT auth.uid())))) OR (SELECT check_permission((SELECT auth.uid()), 'sales.orders.read_all'::text)))
```

---

### `sales_return_items` — `sri_read`

**USING before:**
```sql
(EXISTS ( SELECT 1
   FROM sales_returns sr
  WHERE ((sr.id = sales_return_items.return_id) AND ((sr.created_by = auth.uid()) OR check_permission(auth.uid(), 'sales.returns.read'::text)))))
```

**USING after:**
```sql
(EXISTS ( SELECT 1
   FROM sales_returns sr
  WHERE ((sr.id = sales_return_items.return_id) AND ((sr.created_by = (SELECT auth.uid())) OR (SELECT check_permission((SELECT auth.uid()), 'sales.returns.read'::text))))))
```

---

### `sales_return_items` — `sri_write`

**USING before:**
```sql
(EXISTS ( SELECT 1
   FROM sales_returns sr
  WHERE ((sr.id = sales_return_items.return_id) AND (sr.status = 'draft'::sales_return_status) AND ((sr.created_by = auth.uid()) OR check_permission(auth.uid(), 'sales.returns.confirm'::text)))))
```

**USING after:**
```sql
(EXISTS ( SELECT 1
   FROM sales_returns sr
  WHERE ((sr.id = sales_return_items.return_id) AND (sr.status = 'draft'::sales_return_status) AND ((sr.created_by = (SELECT auth.uid())) OR (SELECT check_permission((SELECT auth.uid()), 'sales.returns.confirm'::text))))))
```

---

### `sales_returns` — `sr_insert`

**WITH CHECK before:**
```sql
check_permission(auth.uid(), 'sales.returns.create'::text)
```

**WITH CHECK after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'sales.returns.create'::text))
```

---

### `sales_returns` — `sr_read`

**USING before:**
```sql
((created_by = auth.uid()) OR check_permission(auth.uid(), 'sales.returns.read'::text))
```

**USING after:**
```sql
((created_by = (SELECT auth.uid())) OR (SELECT check_permission((SELECT auth.uid()), 'sales.returns.read'::text)))
```

---

### `sales_returns` — `sr_update`

**USING before:**
```sql
(((status = 'draft'::sales_return_status) AND (created_by = auth.uid())) OR check_permission(auth.uid(), 'sales.returns.confirm'::text))
```

**USING after:**
```sql
(((status = 'draft'::sales_return_status) AND (created_by = (SELECT auth.uid()))) OR (SELECT check_permission((SELECT auth.uid()), 'sales.returns.confirm'::text)))
```

---

### `shipping_companies` — `shipping_read`

**USING before:**
```sql
(auth.uid() IS NOT NULL)
```

**USING after:**
```sql
((SELECT auth.uid()) IS NOT NULL)
```

---

### `shipping_companies` — `shipping_write`

**USING before:**
```sql
check_permission(auth.uid(), 'sales.shipping.manage'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'sales.shipping.manage'::text))
```

---

### `stock` — `stock_read`

**USING before:**
```sql
(check_permission(auth.uid(), 'inventory.read_all'::text) OR (check_permission(auth.uid(), 'inventory.read'::text) AND (warehouse_id IN ( SELECT user_warehouse_ids_set() AS user_warehouse_ids_set))))
```

**USING after:**
```sql
((SELECT check_permission((SELECT auth.uid()), 'inventory.read_all'::text)) OR ((SELECT check_permission((SELECT auth.uid()), 'inventory.read'::text)) AND (warehouse_id IN ( SELECT user_warehouse_ids_set() AS user_warehouse_ids_set))))
```

---

### `stock_adjustment_items` — `adjustment_items_read`

**USING before:**
```sql
(check_permission(auth.uid(), 'inventory.read_all'::text) OR (adjustment_id IN ( SELECT stock_adjustments.id
   FROM stock_adjustments
  WHERE ((stock_adjustments.created_by = auth.uid()) OR (stock_adjustments.warehouse_id IN ( SELECT user_warehouse_ids_set() AS user_warehouse_ids_set))))))
```

**USING after:**
```sql
((SELECT check_permission((SELECT auth.uid()), 'inventory.read_all'::text)) OR (adjustment_id IN ( SELECT stock_adjustments.id
   FROM stock_adjustments
  WHERE ((stock_adjustments.created_by = (SELECT auth.uid())) OR (stock_adjustments.warehouse_id IN ( SELECT user_warehouse_ids_set() AS user_warehouse_ids_set))))))
```

---

### `stock_adjustment_items` — `adjustment_items_write`

**USING before:**
```sql
check_permission(auth.uid(), 'inventory.adjustments.create'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'inventory.adjustments.create'::text))
```

---

### `stock_adjustments` — `adjustments_read`

**USING before:**
```sql
(check_permission(auth.uid(), 'inventory.read_all'::text) OR (created_by = auth.uid()) OR (check_permission(auth.uid(), 'inventory.adjustments.read'::text) AND (warehouse_id IN ( SELECT user_warehouse_ids_set() AS user_warehouse_ids_set))))
```

**USING after:**
```sql
((SELECT check_permission((SELECT auth.uid()), 'inventory.read_all'::text)) OR (created_by = (SELECT auth.uid())) OR ((SELECT check_permission((SELECT auth.uid()), 'inventory.adjustments.read'::text)) AND (warehouse_id IN ( SELECT user_warehouse_ids_set() AS user_warehouse_ids_set))))
```

---

### `stock_adjustments` — `adjustments_write`

**USING before:**
```sql
check_permission(auth.uid(), 'inventory.adjustments.create'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'inventory.adjustments.create'::text))
```

---

### `stock_batches` — `stock_batches_read`

**USING before:**
```sql
(check_permission(auth.uid(), 'inventory.read_all'::text) OR (check_permission(auth.uid(), 'inventory.read'::text) AND (stock_id IN ( SELECT stock.id
   FROM stock
  WHERE (stock.warehouse_id IN ( SELECT user_warehouse_ids_set() AS user_warehouse_ids_set))))))
```

**USING after:**
```sql
((SELECT check_permission((SELECT auth.uid()), 'inventory.read_all'::text)) OR ((SELECT check_permission((SELECT auth.uid()), 'inventory.read'::text)) AND (stock_id IN ( SELECT stock.id
   FROM stock
  WHERE (stock.warehouse_id IN ( SELECT user_warehouse_ids_set() AS user_warehouse_ids_set))))))
```

---

### `stock_movements` — `stock_movements_read`

**USING before:**
```sql
(check_permission(auth.uid(), 'inventory.read_all'::text) OR (check_permission(auth.uid(), 'inventory.read'::text) AND (warehouse_id IN ( SELECT user_warehouse_ids_set() AS user_warehouse_ids_set))))
```

**USING after:**
```sql
((SELECT check_permission((SELECT auth.uid()), 'inventory.read_all'::text)) OR ((SELECT check_permission((SELECT auth.uid()), 'inventory.read'::text)) AND (warehouse_id IN ( SELECT user_warehouse_ids_set() AS user_warehouse_ids_set))))
```

---

### `stock_transfer_items` — `transfer_items_read`

**USING before:**
```sql
(check_permission(auth.uid(), 'inventory.read_all'::text) OR (transfer_id IN ( SELECT stock_transfers.id
   FROM stock_transfers
  WHERE ((stock_transfers.requested_by = auth.uid()) OR (stock_transfers.from_warehouse_id IN ( SELECT user_warehouse_ids_set() AS user_warehouse_ids_set)) OR (stock_transfers.to_warehouse_id IN ( SELECT user_warehouse_ids_set() AS user_warehouse_ids_set))))))
```

**USING after:**
```sql
((SELECT check_permission((SELECT auth.uid()), 'inventory.read_all'::text)) OR (transfer_id IN ( SELECT stock_transfers.id
   FROM stock_transfers
  WHERE ((stock_transfers.requested_by = (SELECT auth.uid())) OR (stock_transfers.from_warehouse_id IN ( SELECT user_warehouse_ids_set() AS user_warehouse_ids_set)) OR (stock_transfers.to_warehouse_id IN ( SELECT user_warehouse_ids_set() AS user_warehouse_ids_set))))))
```

---

### `stock_transfer_items` — `transfer_items_write`

**USING before:**
```sql
check_permission(auth.uid(), 'inventory.transfers.create'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'inventory.transfers.create'::text))
```

---

### `stock_transfers` — `transfers_read`

**USING before:**
```sql
(check_permission(auth.uid(), 'inventory.read_all'::text) OR (requested_by = auth.uid()) OR (check_permission(auth.uid(), 'inventory.transfers.read'::text) AND ((from_warehouse_id IN ( SELECT user_warehouse_ids_set() AS user_warehouse_ids_set)) OR (to_warehouse_id IN ( SELECT user_warehouse_ids_set() AS user_warehouse_ids_set)))))
```

**USING after:**
```sql
((SELECT check_permission((SELECT auth.uid()), 'inventory.read_all'::text)) OR (requested_by = (SELECT auth.uid())) OR ((SELECT check_permission((SELECT auth.uid()), 'inventory.transfers.read'::text)) AND ((from_warehouse_id IN ( SELECT user_warehouse_ids_set() AS user_warehouse_ids_set)) OR (to_warehouse_id IN ( SELECT user_warehouse_ids_set() AS user_warehouse_ids_set)))))
```

---

### `stock_transfers` — `transfers_write`

**USING before:**
```sql
check_permission(auth.uid(), 'inventory.transfers.create'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'inventory.transfers.create'::text))
```

---

### `supplier_contacts` — `supplier_contacts_read`

**USING before:**
```sql
check_permission(auth.uid(), 'suppliers.read'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'suppliers.read'::text))
```

---

### `supplier_contacts` — `supplier_contacts_write`

**USING before:**
```sql
check_permission(auth.uid(), 'suppliers.update'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'suppliers.update'::text))
```

---

### `supplier_ledger` — `supp_ledger_read`

**USING before:**
```sql
check_permission(auth.uid(), 'finance.ledger.read'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'finance.ledger.read'::text))
```

---

### `supplier_ledger` — `supp_ledger_write`

**USING before:**
```sql
check_permission(auth.uid(), 'finance.ledger.adjust'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'finance.ledger.adjust'::text))
```

---

### `supplier_payment_reminders` — `payment_reminders_read`

**USING before:**
```sql
check_permission(auth.uid(), 'suppliers.read'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'suppliers.read'::text))
```

---

### `supplier_payment_reminders` — `payment_reminders_write`

**USING before:**
```sql
check_permission(auth.uid(), 'suppliers.update'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'suppliers.update'::text))
```

---

### `supplier_payment_vouchers` — `spv_insert`

**WITH CHECK before:**
```sql
check_permission(auth.uid(), 'procurement.invoices.pay'::text)
```

**WITH CHECK after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'procurement.invoices.pay'::text))
```

---

### `supplier_payment_vouchers` — `spv_read`

**USING before:**
```sql
(check_permission(auth.uid(), 'procurement.invoices.pay'::text) OR check_permission(auth.uid(), 'procurement.invoices.read'::text))
```

**USING after:**
```sql
((SELECT check_permission((SELECT auth.uid()), 'procurement.invoices.pay'::text)) OR (SELECT check_permission((SELECT auth.uid()), 'procurement.invoices.read'::text)))
```

---

### `supplier_payment_vouchers` — `spv_update`

**USING before:**
```sql
check_permission(auth.uid(), 'procurement.invoices.pay'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'procurement.invoices.pay'::text))
```

---

### `suppliers` — `suppliers_delete`

**USING before:**
```sql
check_permission(auth.uid(), 'suppliers.delete'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'suppliers.delete'::text))
```

---

### `suppliers` — `suppliers_read`

**USING before:**
```sql
check_permission(auth.uid(), 'suppliers.read'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'suppliers.read'::text))
```

---

### `suppliers` — `suppliers_update`

**USING before:**
```sql
check_permission(auth.uid(), 'suppliers.update'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'suppliers.update'::text))
```

---

### `suppliers` — `suppliers_write`

**WITH CHECK before:**
```sql
check_permission(auth.uid(), 'suppliers.create'::text)
```

**WITH CHECK after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'suppliers.create'::text))
```

---

### `target_adjustments` — `ta_read`

**USING before:**
```sql
(check_permission(auth.uid(), 'targets.read_team'::text) OR check_permission(auth.uid(), 'targets.read_all'::text))
```

**USING after:**
```sql
((SELECT check_permission((SELECT auth.uid()), 'targets.read_team'::text)) OR (SELECT check_permission((SELECT auth.uid()), 'targets.read_all'::text)))
```

---

### `target_customers` — `tc_read`

**USING before:**
```sql
((EXISTS ( SELECT 1
   FROM targets t
  WHERE ((t.id = target_customers.target_id) AND (t.assigned_by = auth.uid())))) OR (EXISTS ( SELECT 1
   FROM (targets t
     JOIN hr_employees he ON ((he.id = t.scope_id)))
  WHERE ((t.id = target_customers.target_id) AND ((t.scope)::text = 'individual'::text) AND (he.user_id = auth.uid())))) OR check_permission(auth.uid(), 'targets.read_all'::text) OR check_permission(auth.uid(), 'targets.rewards.view'::text) OR check_permission(auth.uid(), 'targets.rewards.configure'::text))
```

**USING after:**
```sql
((EXISTS ( SELECT 1
   FROM targets t
  WHERE ((t.id = target_customers.target_id) AND (t.assigned_by = (SELECT auth.uid()))))) OR (EXISTS ( SELECT 1
   FROM (targets t
     JOIN hr_employees he ON ((he.id = t.scope_id)))
  WHERE ((t.id = target_customers.target_id) AND ((t.scope)::text = 'individual'::text) AND (he.user_id = (SELECT auth.uid()))))) OR (SELECT check_permission((SELECT auth.uid()), 'targets.read_all'::text)) OR (SELECT check_permission((SELECT auth.uid()), 'targets.rewards.view'::text)) OR (SELECT check_permission((SELECT auth.uid()), 'targets.rewards.configure'::text)))
```

---

### `target_customers` — `tc_write`

**USING before:**
```sql
(check_permission(auth.uid(), 'targets.create'::text) OR check_permission(auth.uid(), 'targets.read_all'::text) OR check_permission(auth.uid(), 'targets.rewards.configure'::text))
```

**USING after:**
```sql
((SELECT check_permission((SELECT auth.uid()), 'targets.create'::text)) OR (SELECT check_permission((SELECT auth.uid()), 'targets.read_all'::text)) OR (SELECT check_permission((SELECT auth.uid()), 'targets.rewards.configure'::text)))
```

---

### `target_payout_clawbacks` — `clawback_select`

**USING before:**
```sql
(check_permission(auth.uid(), 'hr.payroll.read'::text) OR check_permission(auth.uid(), 'hr.adjustments.read'::text) OR check_permission(auth.uid(), 'targets.view'::text))
```

**USING after:**
```sql
((SELECT check_permission((SELECT auth.uid()), 'hr.payroll.read'::text)) OR (SELECT check_permission((SELECT auth.uid()), 'hr.adjustments.read'::text)) OR (SELECT check_permission((SELECT auth.uid()), 'targets.view'::text)))
```

---

### `target_progress` — `tp_read`

**USING before:**
```sql
(EXISTS ( SELECT 1
   FROM targets t
  WHERE ((t.id = target_progress.target_id) AND ((((t.scope)::text = 'individual'::text) AND (t.scope_id IN ( SELECT hr_employees.id
           FROM hr_employees
          WHERE (hr_employees.user_id = auth.uid())))) OR (check_permission(auth.uid(), 'targets.read_team'::text) AND ((((t.scope)::text = 'branch'::text) AND (t.scope_id = ( SELECT hr_employees.branch_id
           FROM hr_employees
          WHERE (hr_employees.user_id = auth.uid())
         LIMIT 1))) OR (((t.scope)::text = 'individual'::text) AND (t.scope_id IN ( SELECT hr_employees.id
           FROM hr_employees
          WHERE (hr_employees.branch_id = ( SELECT hr_employees_1.branch_id
                   FROM hr_employees hr_employees_1
                  WHERE (hr_employees_1.user_id = auth.uid())
                 LIMIT 1))))))) OR check_permission(auth.uid(), 'targets.read_all'::text)))))
```

**USING after:**
```sql
(EXISTS ( SELECT 1
   FROM targets t
  WHERE ((t.id = target_progress.target_id) AND ((((t.scope)::text = 'individual'::text) AND (t.scope_id IN ( SELECT hr_employees.id
           FROM hr_employees
          WHERE (hr_employees.user_id = (SELECT auth.uid()))))) OR ((SELECT check_permission((SELECT auth.uid()), 'targets.read_team'::text)) AND ((((t.scope)::text = 'branch'::text) AND (t.scope_id = ( SELECT hr_employees.branch_id
           FROM hr_employees
          WHERE (hr_employees.user_id = (SELECT auth.uid()))
         LIMIT 1))) OR (((t.scope)::text = 'individual'::text) AND (t.scope_id IN ( SELECT hr_employees.id
           FROM hr_employees
          WHERE (hr_employees.branch_id = ( SELECT hr_employees_1.branch_id
                   FROM hr_employees hr_employees_1
                  WHERE (hr_employees_1.user_id = (SELECT auth.uid()))
                 LIMIT 1))))))) OR (SELECT check_permission((SELECT auth.uid()), 'targets.read_all'::text))))))
```

---

### `target_reward_payouts` — `trp_read`

**USING before:**
```sql
((employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.user_id = auth.uid()))) OR check_permission(auth.uid(), 'targets.read_all'::text) OR check_permission(auth.uid(), 'hr.payroll.read'::text))
```

**USING after:**
```sql
((employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.user_id = (SELECT auth.uid())))) OR (SELECT check_permission((SELECT auth.uid()), 'targets.read_all'::text)) OR (SELECT check_permission((SELECT auth.uid()), 'hr.payroll.read'::text)))
```

---

### `target_reward_tiers` — `trt_read`

**USING before:**
```sql
((EXISTS ( SELECT 1
   FROM targets t
  WHERE ((t.id = target_reward_tiers.target_id) AND (t.assigned_by = auth.uid())))) OR (EXISTS ( SELECT 1
   FROM (targets t
     JOIN hr_employees he ON ((he.id = t.scope_id)))
  WHERE ((t.id = target_reward_tiers.target_id) AND ((t.scope)::text = 'individual'::text) AND (he.user_id = auth.uid())))) OR check_permission(auth.uid(), 'targets.read_all'::text) OR check_permission(auth.uid(), 'targets.rewards.view'::text) OR check_permission(auth.uid(), 'targets.rewards.configure'::text))
```

**USING after:**
```sql
((EXISTS ( SELECT 1
   FROM targets t
  WHERE ((t.id = target_reward_tiers.target_id) AND (t.assigned_by = (SELECT auth.uid()))))) OR (EXISTS ( SELECT 1
   FROM (targets t
     JOIN hr_employees he ON ((he.id = t.scope_id)))
  WHERE ((t.id = target_reward_tiers.target_id) AND ((t.scope)::text = 'individual'::text) AND (he.user_id = (SELECT auth.uid()))))) OR (SELECT check_permission((SELECT auth.uid()), 'targets.read_all'::text)) OR (SELECT check_permission((SELECT auth.uid()), 'targets.rewards.view'::text)) OR (SELECT check_permission((SELECT auth.uid()), 'targets.rewards.configure'::text)))
```

---

### `target_reward_tiers` — `trt_write`

**USING before:**
```sql
(check_permission(auth.uid(), 'targets.create'::text) OR check_permission(auth.uid(), 'targets.read_all'::text) OR check_permission(auth.uid(), 'targets.rewards.configure'::text))
```

**USING after:**
```sql
((SELECT check_permission((SELECT auth.uid()), 'targets.create'::text)) OR (SELECT check_permission((SELECT auth.uid()), 'targets.read_all'::text)) OR (SELECT check_permission((SELECT auth.uid()), 'targets.rewards.configure'::text)))
```

---

### `target_types` — `target_types_read`

**USING before:**
```sql
(auth.uid() IS NOT NULL)
```

**USING after:**
```sql
((SELECT auth.uid()) IS NOT NULL)
```

---

### `target_types` — `tgt_types_read`

**USING before:**
```sql
(auth.uid() IS NOT NULL)
```

**USING after:**
```sql
((SELECT auth.uid()) IS NOT NULL)
```

---

### `target_types` — `tgt_types_write`

**USING before:**
```sql
check_permission(auth.uid(), 'settings.update'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'settings.update'::text))
```

---

### `targets` — `tgt_insert`

**WITH CHECK before:**
```sql
(check_permission(auth.uid(), 'targets.read_all'::text) OR ((check_permission(auth.uid(), 'targets.create'::text) OR check_permission(auth.uid(), 'targets.assign'::text)) AND ((((scope)::text = 'individual'::text) AND (scope_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.branch_id = ( SELECT hr_employees_1.branch_id
           FROM hr_employees hr_employees_1
          WHERE (hr_employees_1.user_id = auth.uid())
         LIMIT 1))))) OR (((scope)::text = 'branch'::text) AND (scope_id = ( SELECT hr_employees.branch_id
   FROM hr_employees
  WHERE (hr_employees.user_id = auth.uid())
 LIMIT 1))) OR (((scope)::text = 'department'::text) AND (scope_id IN ( SELECT hr_departments.id
   FROM hr_departments
  WHERE (hr_departments.branch_id = ( SELECT hr_employees.branch_id
           FROM hr_employees
          WHERE (hr_employees.user_id = auth.uid())
         LIMIT 1))))))))
```

**WITH CHECK after:**
```sql
((SELECT check_permission((SELECT auth.uid()), 'targets.read_all'::text)) OR (((SELECT check_permission((SELECT auth.uid()), 'targets.create'::text)) OR (SELECT check_permission((SELECT auth.uid()), 'targets.assign'::text))) AND ((((scope)::text = 'individual'::text) AND (scope_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.branch_id = ( SELECT hr_employees_1.branch_id
           FROM hr_employees hr_employees_1
          WHERE (hr_employees_1.user_id = (SELECT auth.uid()))
         LIMIT 1))))) OR (((scope)::text = 'branch'::text) AND (scope_id = ( SELECT hr_employees.branch_id
   FROM hr_employees
  WHERE (hr_employees.user_id = (SELECT auth.uid()))
 LIMIT 1))) OR (((scope)::text = 'department'::text) AND (scope_id IN ( SELECT hr_departments.id
   FROM hr_departments
  WHERE (hr_departments.branch_id = ( SELECT hr_employees.branch_id
           FROM hr_employees
          WHERE (hr_employees.user_id = (SELECT auth.uid()))
         LIMIT 1))))))))
```

---

### `targets` — `tgt_read`

**USING before:**
```sql
((((scope)::text = 'individual'::text) AND (scope_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.user_id = auth.uid())))) OR (check_permission(auth.uid(), 'targets.read_team'::text) AND ((((scope)::text = 'branch'::text) AND (scope_id = ( SELECT hr_employees.branch_id
   FROM hr_employees
  WHERE (hr_employees.user_id = auth.uid())
 LIMIT 1))) OR (((scope)::text = 'individual'::text) AND (scope_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.branch_id = ( SELECT hr_employees_1.branch_id
           FROM hr_employees hr_employees_1
          WHERE (hr_employees_1.user_id = auth.uid())
         LIMIT 1))))))) OR check_permission(auth.uid(), 'targets.read_all'::text))
```

**USING after:**
```sql
((((scope)::text = 'individual'::text) AND (scope_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.user_id = (SELECT auth.uid()))))) OR ((SELECT check_permission((SELECT auth.uid()), 'targets.read_team'::text)) AND ((((scope)::text = 'branch'::text) AND (scope_id = ( SELECT hr_employees.branch_id
   FROM hr_employees
  WHERE (hr_employees.user_id = (SELECT auth.uid()))
 LIMIT 1))) OR (((scope)::text = 'individual'::text) AND (scope_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.branch_id = ( SELECT hr_employees_1.branch_id
           FROM hr_employees hr_employees_1
          WHERE (hr_employees_1.user_id = (SELECT auth.uid()))
         LIMIT 1))))))) OR (SELECT check_permission((SELECT auth.uid()), 'targets.read_all'::text)))
```

---

### `targets` — `tgt_update`

**USING before:**
```sql
(check_permission(auth.uid(), 'targets.read_all'::text) OR ((check_permission(auth.uid(), 'targets.update'::text) OR check_permission(auth.uid(), 'targets.assign'::text)) AND ((((scope)::text = 'individual'::text) AND (scope_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.branch_id = ( SELECT hr_employees_1.branch_id
           FROM hr_employees hr_employees_1
          WHERE (hr_employees_1.user_id = auth.uid())))))) OR (((scope)::text = 'branch'::text) AND (scope_id = ( SELECT hr_employees.branch_id
   FROM hr_employees
  WHERE (hr_employees.user_id = auth.uid())))) OR (((scope)::text = 'department'::text) AND (scope_id IN ( SELECT hr_departments.id
   FROM hr_departments
  WHERE (hr_departments.branch_id = ( SELECT hr_employees.branch_id
           FROM hr_employees
          WHERE (hr_employees.user_id = auth.uid())))))))))
```

**USING after:**
```sql
((SELECT check_permission((SELECT auth.uid()), 'targets.read_all'::text)) OR (((SELECT check_permission((SELECT auth.uid()), 'targets.update'::text)) OR (SELECT check_permission((SELECT auth.uid()), 'targets.assign'::text))) AND ((((scope)::text = 'individual'::text) AND (scope_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.branch_id = ( SELECT hr_employees_1.branch_id
           FROM hr_employees hr_employees_1
          WHERE (hr_employees_1.user_id = (SELECT auth.uid()))))))) OR (((scope)::text = 'branch'::text) AND (scope_id = ( SELECT hr_employees.branch_id
   FROM hr_employees
  WHERE (hr_employees.user_id = (SELECT auth.uid()))))) OR (((scope)::text = 'department'::text) AND (scope_id IN ( SELECT hr_departments.id
   FROM hr_departments
  WHERE (hr_departments.branch_id = ( SELECT hr_employees.branch_id
           FROM hr_employees
          WHERE (hr_employees.user_id = (SELECT auth.uid()))))))))))
```

**WITH CHECK before:**
```sql
(check_permission(auth.uid(), 'targets.read_all'::text) OR ((check_permission(auth.uid(), 'targets.update'::text) OR check_permission(auth.uid(), 'targets.assign'::text)) AND ((((scope)::text = 'individual'::text) AND (scope_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.branch_id = ( SELECT hr_employees_1.branch_id
           FROM hr_employees hr_employees_1
          WHERE (hr_employees_1.user_id = auth.uid())))))) OR (((scope)::text = 'branch'::text) AND (scope_id = ( SELECT hr_employees.branch_id
   FROM hr_employees
  WHERE (hr_employees.user_id = auth.uid())))) OR (((scope)::text = 'department'::text) AND (scope_id IN ( SELECT hr_departments.id
   FROM hr_departments
  WHERE (hr_departments.branch_id = ( SELECT hr_employees.branch_id
           FROM hr_employees
          WHERE (hr_employees.user_id = auth.uid())))))))))
```

**WITH CHECK after:**
```sql
((SELECT check_permission((SELECT auth.uid()), 'targets.read_all'::text)) OR (((SELECT check_permission((SELECT auth.uid()), 'targets.update'::text)) OR (SELECT check_permission((SELECT auth.uid()), 'targets.assign'::text))) AND ((((scope)::text = 'individual'::text) AND (scope_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.branch_id = ( SELECT hr_employees_1.branch_id
           FROM hr_employees hr_employees_1
          WHERE (hr_employees_1.user_id = (SELECT auth.uid()))))))) OR (((scope)::text = 'branch'::text) AND (scope_id = ( SELECT hr_employees.branch_id
   FROM hr_employees
  WHERE (hr_employees.user_id = (SELECT auth.uid()))))) OR (((scope)::text = 'department'::text) AND (scope_id IN ( SELECT hr_departments.id
   FROM hr_departments
  WHERE (hr_departments.branch_id = ( SELECT hr_employees.branch_id
           FROM hr_employees
          WHERE (hr_employees.user_id = (SELECT auth.uid()))))))))))
```

---

### `units` — `units_read`

**USING before:**
```sql
(auth.uid() IS NOT NULL)
```

**USING after:**
```sql
((SELECT auth.uid()) IS NOT NULL)
```

---

### `units` — `units_write`

**USING before:**
```sql
check_permission(auth.uid(), 'products.create'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'products.create'::text))
```

---

### `user_permission_overrides` — `overrides_select`

**USING before:**
```sql
((user_id = auth.uid()) OR check_permission(auth.uid(), 'auth.users.read'::text))
```

**USING after:**
```sql
((user_id = (SELECT auth.uid())) OR (SELECT check_permission((SELECT auth.uid()), 'auth.users.read'::text)))
```

---

### `user_permission_overrides` — `overrides_write`

**USING before:**
```sql
check_permission(auth.uid(), 'auth.users.update'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'auth.users.update'::text))
```

---

### `user_roles` — `user_roles_delete`

**USING before:**
```sql
check_permission(auth.uid(), 'auth.users.update'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'auth.users.update'::text))
```

---

### `user_roles` — `user_roles_insert`

**WITH CHECK before:**
```sql
check_permission(auth.uid(), 'auth.users.update'::text)
```

**WITH CHECK after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'auth.users.update'::text))
```

---

### `user_roles` — `user_roles_select`

**USING before:**
```sql
((user_id = auth.uid()) OR check_permission(auth.uid(), 'auth.users.read'::text))
```

**USING after:**
```sql
((user_id = (SELECT auth.uid())) OR (SELECT check_permission((SELECT auth.uid()), 'auth.users.read'::text)))
```

---

### `user_roles` — `user_roles_update`

**USING before:**
```sql
check_permission(auth.uid(), 'auth.users.update'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'auth.users.update'::text))
```

---

### `vault_transactions` — `vault_txn_read`

**USING before:**
```sql
(check_permission(auth.uid(), 'finance.vaults.read_all'::text) OR (check_permission(auth.uid(), 'finance.vaults.read'::text) AND (vault_id IN ( SELECT vaults.id
   FROM vaults
  WHERE (vaults.responsible_id = auth.uid())))))
```

**USING after:**
```sql
((SELECT check_permission((SELECT auth.uid()), 'finance.vaults.read_all'::text)) OR ((SELECT check_permission((SELECT auth.uid()), 'finance.vaults.read'::text)) AND (vault_id IN ( SELECT vaults.id
   FROM vaults
  WHERE (vaults.responsible_id = (SELECT auth.uid()))))))
```

---

### `vault_transactions` — `vault_txn_write`

**USING before:**
```sql
check_permission(auth.uid(), 'finance.vaults.transact'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'finance.vaults.transact'::text))
```

---

### `vaults` — `vaults_insert`

**WITH CHECK before:**
```sql
check_permission(auth.uid(), 'finance.vaults.create'::text)
```

**WITH CHECK after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'finance.vaults.create'::text))
```

---

### `vaults` — `vaults_read`

**USING before:**
```sql
(check_permission(auth.uid(), 'finance.vaults.read_all'::text) OR (check_permission(auth.uid(), 'finance.vaults.read'::text) AND (responsible_id = auth.uid())))
```

**USING after:**
```sql
((SELECT check_permission((SELECT auth.uid()), 'finance.vaults.read_all'::text)) OR ((SELECT check_permission((SELECT auth.uid()), 'finance.vaults.read'::text)) AND (responsible_id = (SELECT auth.uid()))))
```

---

### `vaults` — `vaults_update`

**USING before:**
```sql
check_permission(auth.uid(), 'finance.vaults.update'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'finance.vaults.update'::text))
```

---

### `visit_checklist_questions` — `checklist_questions_read`

**USING before:**
```sql
(auth.uid() IS NOT NULL)
```

**USING after:**
```sql
((SELECT auth.uid()) IS NOT NULL)
```

---

### `visit_checklist_questions` — `checklist_questions_write`

**USING before:**
```sql
check_permission(auth.uid(), 'checklists.manage'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'checklists.manage'::text))
```

---

### `visit_checklist_responses` — `checklist_responses_insert`

**WITH CHECK before:**
```sql
(check_permission(auth.uid(), 'activities.update_own'::text) OR check_permission(auth.uid(), 'activities.read_team'::text) OR check_permission(auth.uid(), 'activities.read_all'::text))
```

**WITH CHECK after:**
```sql
((SELECT check_permission((SELECT auth.uid()), 'activities.update_own'::text)) OR (SELECT check_permission((SELECT auth.uid()), 'activities.read_team'::text)) OR (SELECT check_permission((SELECT auth.uid()), 'activities.read_all'::text)))
```

---

### `visit_checklist_responses` — `checklist_responses_read`

**USING before:**
```sql
(check_permission(auth.uid(), 'activities.read_all'::text) OR check_permission(auth.uid(), 'activities.read_team'::text) OR (check_permission(auth.uid(), 'activities.update_own'::text) AND (activity_id IN ( SELECT activities.id
   FROM activities
  WHERE (activities.created_by = auth.uid())))))
```

**USING after:**
```sql
((SELECT check_permission((SELECT auth.uid()), 'activities.read_all'::text)) OR (SELECT check_permission((SELECT auth.uid()), 'activities.read_team'::text)) OR ((SELECT check_permission((SELECT auth.uid()), 'activities.update_own'::text)) AND (activity_id IN ( SELECT activities.id
   FROM activities
  WHERE (activities.created_by = (SELECT auth.uid()))))))
```

---

### `visit_checklist_responses` — `checklist_responses_update`

**USING before:**
```sql
(check_permission(auth.uid(), 'activities.update_own'::text) AND (activity_id IN ( SELECT activities.id
   FROM activities
  WHERE (activities.created_by = auth.uid()))))
```

**USING after:**
```sql
((SELECT check_permission((SELECT auth.uid()), 'activities.update_own'::text)) AND (activity_id IN ( SELECT activities.id
   FROM activities
  WHERE (activities.created_by = (SELECT auth.uid())))))
```

---

### `visit_checklist_templates` — `checklist_templates_read`

**USING before:**
```sql
(auth.uid() IS NOT NULL)
```

**USING after:**
```sql
((SELECT auth.uid()) IS NOT NULL)
```

---

### `visit_checklist_templates` — `checklist_templates_write`

**USING before:**
```sql
check_permission(auth.uid(), 'checklists.manage'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'checklists.manage'::text))
```

---

### `visit_plan_items` — `vpi_delete`

**USING before:**
```sql
((check_permission(auth.uid(), 'visit_plans.create'::text) AND (EXISTS ( SELECT 1
   FROM visit_plans vp
  WHERE ((vp.id = visit_plan_items.plan_id) AND (vp.employee_id IN ( SELECT hr_employees.id
           FROM hr_employees
          WHERE (hr_employees.user_id = auth.uid()))))))) OR (check_permission(auth.uid(), 'visit_plans.update'::text) AND (EXISTS ( SELECT 1
   FROM visit_plans vp
  WHERE ((vp.id = visit_plan_items.plan_id) AND (vp.employee_id IN ( SELECT hr_employees.id
           FROM hr_employees
          WHERE (hr_employees.branch_id = ( SELECT hr_employees_1.branch_id
                   FROM hr_employees hr_employees_1
                  WHERE (hr_employees_1.user_id = auth.uid())
                 LIMIT 1)))))))) OR check_permission(auth.uid(), 'visit_plans.read_all'::text))
```

**USING after:**
```sql
(((SELECT check_permission((SELECT auth.uid()), 'visit_plans.create'::text)) AND (EXISTS ( SELECT 1
   FROM visit_plans vp
  WHERE ((vp.id = visit_plan_items.plan_id) AND (vp.employee_id IN ( SELECT hr_employees.id
           FROM hr_employees
          WHERE (hr_employees.user_id = (SELECT auth.uid())))))))) OR ((SELECT check_permission((SELECT auth.uid()), 'visit_plans.update'::text)) AND (EXISTS ( SELECT 1
   FROM visit_plans vp
  WHERE ((vp.id = visit_plan_items.plan_id) AND (vp.employee_id IN ( SELECT hr_employees.id
           FROM hr_employees
          WHERE (hr_employees.branch_id = ( SELECT hr_employees_1.branch_id
                   FROM hr_employees hr_employees_1
                  WHERE (hr_employees_1.user_id = (SELECT auth.uid()))
                 LIMIT 1)))))))) OR (SELECT check_permission((SELECT auth.uid()), 'visit_plans.read_all'::text)))
```

---

### `visit_plan_items` — `vpi_insert`

**WITH CHECK before:**
```sql
((check_permission(auth.uid(), 'visit_plans.create'::text) AND (EXISTS ( SELECT 1
   FROM visit_plans vp
  WHERE ((vp.id = visit_plan_items.plan_id) AND ((vp.employee_id IN ( SELECT hr_employees.id
           FROM hr_employees
          WHERE (hr_employees.user_id = auth.uid()))) OR check_permission(auth.uid(), 'visit_plans.read_team'::text)))))) OR (check_permission(auth.uid(), 'visit_plans.update'::text) AND (EXISTS ( SELECT 1
   FROM visit_plans vp
  WHERE ((vp.id = visit_plan_items.plan_id) AND (vp.employee_id IN ( SELECT hr_employees.id
           FROM hr_employees
          WHERE (hr_employees.branch_id = ( SELECT hr_employees_1.branch_id
                   FROM hr_employees hr_employees_1
                  WHERE (hr_employees_1.user_id = auth.uid())
                 LIMIT 1)))))))) OR check_permission(auth.uid(), 'visit_plans.read_all'::text))
```

**WITH CHECK after:**
```sql
(((SELECT check_permission((SELECT auth.uid()), 'visit_plans.create'::text)) AND (EXISTS ( SELECT 1
   FROM visit_plans vp
  WHERE ((vp.id = visit_plan_items.plan_id) AND ((vp.employee_id IN ( SELECT hr_employees.id
           FROM hr_employees
          WHERE (hr_employees.user_id = (SELECT auth.uid())))) OR (SELECT check_permission((SELECT auth.uid()), 'visit_plans.read_team'::text))))))) OR ((SELECT check_permission((SELECT auth.uid()), 'visit_plans.update'::text)) AND (EXISTS ( SELECT 1
   FROM visit_plans vp
  WHERE ((vp.id = visit_plan_items.plan_id) AND (vp.employee_id IN ( SELECT hr_employees.id
           FROM hr_employees
          WHERE (hr_employees.branch_id = ( SELECT hr_employees_1.branch_id
                   FROM hr_employees hr_employees_1
                  WHERE (hr_employees_1.user_id = (SELECT auth.uid()))
                 LIMIT 1)))))))) OR (SELECT check_permission((SELECT auth.uid()), 'visit_plans.read_all'::text)))
```

---

### `visit_plan_items` — `vpi_read`

**USING before:**
```sql
(EXISTS ( SELECT 1
   FROM visit_plans vp
  WHERE ((vp.id = visit_plan_items.plan_id) AND ((vp.employee_id IN ( SELECT hr_employees.id
           FROM hr_employees
          WHERE (hr_employees.user_id = auth.uid()))) OR check_permission(auth.uid(), 'visit_plans.read_all'::text)))))
```

**USING after:**
```sql
(EXISTS ( SELECT 1
   FROM visit_plans vp
  WHERE ((vp.id = visit_plan_items.plan_id) AND ((vp.employee_id IN ( SELECT hr_employees.id
           FROM hr_employees
          WHERE (hr_employees.user_id = (SELECT auth.uid())))) OR (SELECT check_permission((SELECT auth.uid()), 'visit_plans.read_all'::text))))))
```

---

### `visit_plan_items` — `vpi_update`

**USING before:**
```sql
((check_permission(auth.uid(), 'activities.create'::text) AND (EXISTS ( SELECT 1
   FROM visit_plans vp
  WHERE ((vp.id = visit_plan_items.plan_id) AND (vp.employee_id IN ( SELECT hr_employees.id
           FROM hr_employees
          WHERE (hr_employees.user_id = auth.uid()))))))) OR (check_permission(auth.uid(), 'visit_plans.create'::text) AND (EXISTS ( SELECT 1
   FROM visit_plans vp
  WHERE ((vp.id = visit_plan_items.plan_id) AND (vp.employee_id IN ( SELECT hr_employees.id
           FROM hr_employees
          WHERE (hr_employees.user_id = auth.uid()))))))) OR (check_permission(auth.uid(), 'visit_plans.update'::text) AND (EXISTS ( SELECT 1
   FROM visit_plans vp
  WHERE ((vp.id = visit_plan_items.plan_id) AND (vp.employee_id IN ( SELECT hr_employees.id
           FROM hr_employees
          WHERE (hr_employees.branch_id = ( SELECT hr_employees_1.branch_id
                   FROM hr_employees hr_employees_1
                  WHERE (hr_employees_1.user_id = auth.uid())
                 LIMIT 1)))))))) OR (check_permission(auth.uid(), 'visit_plans.confirm'::text) AND (EXISTS ( SELECT 1
   FROM visit_plans vp
  WHERE ((vp.id = visit_plan_items.plan_id) AND (vp.employee_id IN ( SELECT hr_employees.id
           FROM hr_employees
          WHERE (hr_employees.branch_id = ( SELECT hr_employees_1.branch_id
                   FROM hr_employees hr_employees_1
                  WHERE (hr_employees_1.user_id = auth.uid())
                 LIMIT 1)))))))) OR check_permission(auth.uid(), 'visit_plans.read_all'::text))
```

**USING after:**
```sql
(((SELECT check_permission((SELECT auth.uid()), 'activities.create'::text)) AND (EXISTS ( SELECT 1
   FROM visit_plans vp
  WHERE ((vp.id = visit_plan_items.plan_id) AND (vp.employee_id IN ( SELECT hr_employees.id
           FROM hr_employees
          WHERE (hr_employees.user_id = (SELECT auth.uid())))))))) OR ((SELECT check_permission((SELECT auth.uid()), 'visit_plans.create'::text)) AND (EXISTS ( SELECT 1
   FROM visit_plans vp
  WHERE ((vp.id = visit_plan_items.plan_id) AND (vp.employee_id IN ( SELECT hr_employees.id
           FROM hr_employees
          WHERE (hr_employees.user_id = (SELECT auth.uid())))))))) OR ((SELECT check_permission((SELECT auth.uid()), 'visit_plans.update'::text)) AND (EXISTS ( SELECT 1
   FROM visit_plans vp
  WHERE ((vp.id = visit_plan_items.plan_id) AND (vp.employee_id IN ( SELECT hr_employees.id
           FROM hr_employees
          WHERE (hr_employees.branch_id = ( SELECT hr_employees_1.branch_id
                   FROM hr_employees hr_employees_1
                  WHERE (hr_employees_1.user_id = (SELECT auth.uid()))
                 LIMIT 1)))))))) OR ((SELECT check_permission((SELECT auth.uid()), 'visit_plans.confirm'::text)) AND (EXISTS ( SELECT 1
   FROM visit_plans vp
  WHERE ((vp.id = visit_plan_items.plan_id) AND (vp.employee_id IN ( SELECT hr_employees.id
           FROM hr_employees
          WHERE (hr_employees.branch_id = ( SELECT hr_employees_1.branch_id
                   FROM hr_employees hr_employees_1
                  WHERE (hr_employees_1.user_id = (SELECT auth.uid()))
                 LIMIT 1)))))))) OR (SELECT check_permission((SELECT auth.uid()), 'visit_plans.read_all'::text)))
```

---

### `visit_plan_templates` — `vpt_insert`

**WITH CHECK before:**
```sql
(check_permission(auth.uid(), 'visit_plans.create'::text) AND ((branch_id IS NULL) OR (branch_id IN ( SELECT hr_employees.branch_id
   FROM hr_employees
  WHERE (hr_employees.user_id = auth.uid()))) OR check_permission(auth.uid(), 'visit_plans.read_all'::text)))
```

**WITH CHECK after:**
```sql
((SELECT check_permission((SELECT auth.uid()), 'visit_plans.create'::text)) AND ((branch_id IS NULL) OR (branch_id IN ( SELECT hr_employees.branch_id
   FROM hr_employees
  WHERE (hr_employees.user_id = (SELECT auth.uid())))) OR (SELECT check_permission((SELECT auth.uid()), 'visit_plans.read_all'::text))))
```

---

### `visit_plan_templates` — `vpt_read`

**USING before:**
```sql
(auth.uid() IS NOT NULL)
```

**USING after:**
```sql
((SELECT auth.uid()) IS NOT NULL)
```

---

### `visit_plan_templates` — `vpt_update`

**USING before:**
```sql
((check_permission(auth.uid(), 'visit_plans.create'::text) AND ((created_by = auth.uid()) OR (employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.branch_id = ( SELECT hr_employees_1.branch_id
           FROM hr_employees hr_employees_1
          WHERE (hr_employees_1.user_id = auth.uid()))))) OR (branch_id IN ( SELECT hr_employees.branch_id
   FROM hr_employees
  WHERE (hr_employees.user_id = auth.uid()))))) OR check_permission(auth.uid(), 'visit_plans.read_all'::text))
```

**USING after:**
```sql
(((SELECT check_permission((SELECT auth.uid()), 'visit_plans.create'::text)) AND ((created_by = (SELECT auth.uid())) OR (employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.branch_id = ( SELECT hr_employees_1.branch_id
           FROM hr_employees hr_employees_1
          WHERE (hr_employees_1.user_id = (SELECT auth.uid())))))) OR (branch_id IN ( SELECT hr_employees.branch_id
   FROM hr_employees
  WHERE (hr_employees.user_id = (SELECT auth.uid())))))) OR (SELECT check_permission((SELECT auth.uid()), 'visit_plans.read_all'::text)))
```

**WITH CHECK before:**
```sql
((check_permission(auth.uid(), 'visit_plans.create'::text) AND ((created_by = auth.uid()) OR (employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.branch_id = ( SELECT hr_employees_1.branch_id
           FROM hr_employees hr_employees_1
          WHERE (hr_employees_1.user_id = auth.uid()))))) OR (branch_id IN ( SELECT hr_employees.branch_id
   FROM hr_employees
  WHERE (hr_employees.user_id = auth.uid()))))) OR check_permission(auth.uid(), 'visit_plans.read_all'::text))
```

**WITH CHECK after:**
```sql
(((SELECT check_permission((SELECT auth.uid()), 'visit_plans.create'::text)) AND ((created_by = (SELECT auth.uid())) OR (employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.branch_id = ( SELECT hr_employees_1.branch_id
           FROM hr_employees hr_employees_1
          WHERE (hr_employees_1.user_id = (SELECT auth.uid())))))) OR (branch_id IN ( SELECT hr_employees.branch_id
   FROM hr_employees
  WHERE (hr_employees.user_id = (SELECT auth.uid())))))) OR (SELECT check_permission((SELECT auth.uid()), 'visit_plans.read_all'::text)))
```

---

### `visit_plan_templates` — `vpt_write`

**USING before:**
```sql
check_permission(auth.uid(), 'visit_plans.create'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'visit_plans.create'::text))
```

---

### `visit_plans` — `vp_insert`

**WITH CHECK before:**
```sql
(check_permission(auth.uid(), 'visit_plans.create'::text) AND ((employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.user_id = auth.uid()))) OR (check_permission(auth.uid(), 'visit_plans.read_team'::text) AND (employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.branch_id = ( SELECT hr_employees_1.branch_id
           FROM hr_employees hr_employees_1
          WHERE (hr_employees_1.user_id = auth.uid())))))) OR check_permission(auth.uid(), 'visit_plans.read_all'::text)))
```

**WITH CHECK after:**
```sql
((SELECT check_permission((SELECT auth.uid()), 'visit_plans.create'::text)) AND ((employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.user_id = (SELECT auth.uid())))) OR ((SELECT check_permission((SELECT auth.uid()), 'visit_plans.read_team'::text)) AND (employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.branch_id = ( SELECT hr_employees_1.branch_id
           FROM hr_employees hr_employees_1
          WHERE (hr_employees_1.user_id = (SELECT auth.uid()))))))) OR (SELECT check_permission((SELECT auth.uid()), 'visit_plans.read_all'::text))))
```

---

### `visit_plans` — `vp_read`

**USING before:**
```sql
((employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.user_id = auth.uid()))) OR (check_permission(auth.uid(), 'visit_plans.read_team'::text) AND (employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.branch_id = ( SELECT hr_employees_1.branch_id
           FROM hr_employees hr_employees_1
          WHERE (hr_employees_1.user_id = auth.uid())
         LIMIT 1))))) OR check_permission(auth.uid(), 'visit_plans.read_all'::text))
```

**USING after:**
```sql
((employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.user_id = (SELECT auth.uid())))) OR ((SELECT check_permission((SELECT auth.uid()), 'visit_plans.read_team'::text)) AND (employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.branch_id = ( SELECT hr_employees_1.branch_id
           FROM hr_employees hr_employees_1
          WHERE (hr_employees_1.user_id = (SELECT auth.uid()))
         LIMIT 1))))) OR (SELECT check_permission((SELECT auth.uid()), 'visit_plans.read_all'::text)))
```

---

### `visit_plans` — `vp_update`

**USING before:**
```sql
((check_permission(auth.uid(), 'visit_plans.create'::text) AND (employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.branch_id = ( SELECT hr_employees_1.branch_id
           FROM hr_employees hr_employees_1
          WHERE (hr_employees_1.user_id = auth.uid())))))) OR (check_permission(auth.uid(), 'visit_plans.confirm'::text) AND (employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.branch_id = ( SELECT hr_employees_1.branch_id
           FROM hr_employees hr_employees_1
          WHERE (hr_employees_1.user_id = auth.uid())))))) OR (check_permission(auth.uid(), 'visit_plans.cancel'::text) AND (employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.branch_id = ( SELECT hr_employees_1.branch_id
           FROM hr_employees hr_employees_1
          WHERE (hr_employees_1.user_id = auth.uid())))))) OR check_permission(auth.uid(), 'visit_plans.read_all'::text))
```

**USING after:**
```sql
(((SELECT check_permission((SELECT auth.uid()), 'visit_plans.create'::text)) AND (employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.branch_id = ( SELECT hr_employees_1.branch_id
           FROM hr_employees hr_employees_1
          WHERE (hr_employees_1.user_id = (SELECT auth.uid()))))))) OR ((SELECT check_permission((SELECT auth.uid()), 'visit_plans.confirm'::text)) AND (employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.branch_id = ( SELECT hr_employees_1.branch_id
           FROM hr_employees hr_employees_1
          WHERE (hr_employees_1.user_id = (SELECT auth.uid()))))))) OR ((SELECT check_permission((SELECT auth.uid()), 'visit_plans.cancel'::text)) AND (employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.branch_id = ( SELECT hr_employees_1.branch_id
           FROM hr_employees hr_employees_1
          WHERE (hr_employees_1.user_id = (SELECT auth.uid()))))))) OR (SELECT check_permission((SELECT auth.uid()), 'visit_plans.read_all'::text)))
```

**WITH CHECK before:**
```sql
((check_permission(auth.uid(), 'visit_plans.create'::text) AND (employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.branch_id = ( SELECT hr_employees_1.branch_id
           FROM hr_employees hr_employees_1
          WHERE (hr_employees_1.user_id = auth.uid())))))) OR (check_permission(auth.uid(), 'visit_plans.confirm'::text) AND (employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.branch_id = ( SELECT hr_employees_1.branch_id
           FROM hr_employees hr_employees_1
          WHERE (hr_employees_1.user_id = auth.uid())))))) OR (check_permission(auth.uid(), 'visit_plans.cancel'::text) AND (employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.branch_id = ( SELECT hr_employees_1.branch_id
           FROM hr_employees hr_employees_1
          WHERE (hr_employees_1.user_id = auth.uid())))))) OR check_permission(auth.uid(), 'visit_plans.read_all'::text))
```

**WITH CHECK after:**
```sql
(((SELECT check_permission((SELECT auth.uid()), 'visit_plans.create'::text)) AND (employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.branch_id = ( SELECT hr_employees_1.branch_id
           FROM hr_employees hr_employees_1
          WHERE (hr_employees_1.user_id = (SELECT auth.uid()))))))) OR ((SELECT check_permission((SELECT auth.uid()), 'visit_plans.confirm'::text)) AND (employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.branch_id = ( SELECT hr_employees_1.branch_id
           FROM hr_employees hr_employees_1
          WHERE (hr_employees_1.user_id = (SELECT auth.uid()))))))) OR ((SELECT check_permission((SELECT auth.uid()), 'visit_plans.cancel'::text)) AND (employee_id IN ( SELECT hr_employees.id
   FROM hr_employees
  WHERE (hr_employees.branch_id = ( SELECT hr_employees_1.branch_id
           FROM hr_employees hr_employees_1
          WHERE (hr_employees_1.user_id = (SELECT auth.uid()))))))) OR (SELECT check_permission((SELECT auth.uid()), 'visit_plans.read_all'::text)))
```

---

### `visit_plans` — `vp_write`

**USING before:**
```sql
check_permission(auth.uid(), 'visit_plans.create'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'visit_plans.create'::text))
```

---

### `warehouse_managers` — `wh_managers_read`

**USING before:**
```sql
(check_permission(auth.uid(), 'inventory.read_all'::text) OR (check_permission(auth.uid(), 'inventory.read'::text) AND (warehouse_id IN ( SELECT user_warehouse_ids_set() AS user_warehouse_ids_set))))
```

**USING after:**
```sql
((SELECT check_permission((SELECT auth.uid()), 'inventory.read_all'::text)) OR ((SELECT check_permission((SELECT auth.uid()), 'inventory.read'::text)) AND (warehouse_id IN ( SELECT user_warehouse_ids_set() AS user_warehouse_ids_set))))
```

---

### `warehouse_managers` — `wh_managers_write`

**USING before:**
```sql
check_permission(auth.uid(), 'inventory.create'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'inventory.create'::text))
```

---

### `warehouses` — `warehouses_read`

**USING before:**
```sql
(check_permission(auth.uid(), 'inventory.read_all'::text) OR (check_permission(auth.uid(), 'inventory.read'::text) AND (id IN ( SELECT user_warehouse_ids_set() AS user_warehouse_ids_set))))
```

**USING after:**
```sql
((SELECT check_permission((SELECT auth.uid()), 'inventory.read_all'::text)) OR ((SELECT check_permission((SELECT auth.uid()), 'inventory.read'::text)) AND (id IN ( SELECT user_warehouse_ids_set() AS user_warehouse_ids_set))))
```

---

### `warehouses` — `warehouses_write`

**USING before:**
```sql
check_permission(auth.uid(), 'inventory.create'::text)
```

**USING after:**
```sql
(SELECT check_permission((SELECT auth.uid()), 'inventory.create'::text))
```

---

## Skipped Policies (1)

| Table | Policy | Reason |
|-------|--------|--------|
| notifications | `notifications_insert_service_role` | policy name contains service_role |

