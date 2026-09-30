import { fail } from './core.mjs';

// Commercial pricing is deliberately unpublished until the provider agreement and
// customer rates are approved. This is not a payment or subscription endpoint.
export function payrollOffer() {
  return { name: 'KORLIX Payroll', enterprise_required: true, paid_addon: true,
    billing_scope: 'business', currency: 'USD', billing_period: 'monthly',
    pricing_model: 'company_base_plus_employee', pricing_status: 'pending',
    base_price_cents: null, per_employee_price_cents: null, checkout_available: false,
    message: 'Separate paid add-on for each business. Monthly business fee plus a per-employee fee. Pricing will be provided before you subscribe.' };
}
export function activationPayload(body = {}) {
  if (body.confirmed !== true || !Number.isInteger(body.estimated_employees) || body.estimated_employees < 0 || body.estimated_employees > 100000) {
    fail('Confirm your activation request and enter a valid employee estimate.');
  }
  return { confirmed: true, estimated_employees: body.estimated_employees };
}
