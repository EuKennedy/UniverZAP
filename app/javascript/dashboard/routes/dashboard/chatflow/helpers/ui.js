// Classes dos campos dos painéis do Chatflow, iguais às do editor original.
export const INPUT_CLASS =
  'h-9 px-3 rounded-lg bg-n-alpha-1 border border-n-weak text-sm text-n-slate-12 focus:outline-none focus:border-n-teal-8';
export const TEXTAREA_CLASS =
  'px-3 py-2 rounded-lg bg-n-alpha-1 border border-n-weak text-sm text-n-slate-12 resize-y focus:outline-none focus:border-n-teal-8';
export const LABEL_CLASS = 'text-xs font-medium text-n-slate-11';
export const HINT_CLASS = 'text-[11px] text-n-slate-10 m-0';

export const chipClass = selected =>
  selected
    ? 'border-n-teal-7 bg-n-teal-3 text-n-teal-12'
    : 'border-n-weak text-n-slate-11 hover:border-n-slate-6';
