// App-wide confirm modal. requireConfirm(opts) resolves true/false, like window.confirm
// but styled in-app. Rendered once globally via ConfirmModal in the root layout.
import { writable } from 'svelte/store';

/** @type {import('svelte/store').Writable<null | {title:string, message?:string, confirmText:string, cancelText:string, danger:boolean, resolve:(v:boolean)=>void}>} */
export const confirmStore = writable(null);

/** @param {{title:string, message?:string, confirmText?:string, cancelText?:string, danger?:boolean}} opts @returns {Promise<boolean>} */
export function requireConfirm(opts) {
  return new Promise((resolve) => {
    confirmStore.set({
      title: opts.title,
      message: opts.message,
      confirmText: opts.confirmText ?? 'Confirm',
      cancelText: opts.cancelText ?? 'Cancel',
      danger: opts.danger ?? false,
      resolve
    });
  });
}
