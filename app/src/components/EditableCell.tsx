import { useEffect, useRef, useState } from 'react';

export type SaveOutcome =
  | { status: 'saved' }
  | { status: 'conflict'; message?: string }
  | { status: 'error'; message: string };

interface Props {
  value: string;
  label: string;                         // accessible name, e.g. "MAT code for Door SASL…"
  placeholder?: string;
  inputMode?: 'text' | 'decimal';
  width?: string;
  /** Tidy what was typed (e.g. upper-case a MAT code) before comparing and saving. */
  normalise?: (typed: string) => string;
  /** Return an error message to refuse the value, or null if it's fine. */
  validate?: (value: string) => string | null;
  onSave: (value: string) => Promise<SaveOutcome>;
}

type State = { kind: 'idle' } | { kind: 'saving' } | { kind: 'saved' } | { kind: 'problem'; message: string };

/**
 * A cell you type into; it saves when you press Enter or leave the cell, and shows what
 * happened: saving…, ✓ saved, or a problem (invalid value, conflict, error). Esc undoes.
 */
export function EditableCell({ value, label, placeholder, inputMode = 'text', width, normalise = v => v.trim(), validate, onSave }: Props) {
  const [draft, setDraft] = useState(value);
  const [state, setState] = useState<State>({ kind: 'idle' });
  const saving = useRef(false);

  // Follow the saved value when it changes from outside (reload, someone else's save)
  useEffect(() => { setDraft(value); }, [value]);
  useEffect(() => {
    if (state.kind !== 'saved') return;
    const t = setTimeout(() => setState({ kind: 'idle' }), 1500);
    return () => clearTimeout(t);
  }, [state]);

  async function commit() {
    const next = normalise(draft);
    if (next === normalise(value) || saving.current) { setDraft(value); return; }
    const invalid = validate?.(next);
    if (invalid) { setState({ kind: 'problem', message: invalid }); return; }
    saving.current = true;
    setState({ kind: 'saving' });
    try {
      const out = await onSave(next);
      if (out.status === 'saved') setState({ kind: 'saved' });
      else if (out.status === 'conflict') {
        setDraft(value);
        setState({ kind: 'problem', message: out.message ?? 'Someone else changed this just now. It has been reloaded; please check and try again.' });
      } else setState({ kind: 'problem', message: out.message });
    } catch (e) {
      setState({ kind: 'problem', message: e instanceof Error ? e.message : String(e) });
    } finally {
      saving.current = false;
    }
  }

  const problem = state.kind === 'problem' ? state.message : null;
  return (
    <div className={`cell ${problem ? 'cell--problem' : ''}`}>
      <input
        aria-label={label}
        aria-invalid={problem ? true : undefined}
        value={draft}
        placeholder={placeholder}
        inputMode={inputMode}
        style={width ? { width } : undefined}
        disabled={state.kind === 'saving'}
        onChange={e => { setDraft(e.target.value); if (problem) setState({ kind: 'idle' }); }}
        onBlur={() => void commit()}
        onKeyDown={e => {
          if (e.key === 'Enter') (e.target as HTMLInputElement).blur();
          if (e.key === 'Escape') { setDraft(value); setState({ kind: 'idle' }); }
        }}
      />
      <span className="cell__status" aria-live="polite">
        {state.kind === 'saving' && 'Saving…'}
        {state.kind === 'saved' && '✓ Saved'}
      </span>
      {problem && <div className="cell__problem" role="alert">{problem}</div>}
    </div>
  );
}
