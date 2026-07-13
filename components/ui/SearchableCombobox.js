'use client';

import { ChevronDown, Search, X } from 'lucide-react';
import { useEffect, useId, useMemo, useRef, useState } from 'react';

function defaultGetValue(option) {
  return option?.id ?? option?.value ?? '';
}

function defaultGetLabel(option) {
  return option?.label ?? option?.nama ?? option?.name ?? '';
}

function normalizeSearch(value) {
  return String(value ?? '')
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '');
}

export default function SearchableCombobox({
  options = [],
  value = '',
  onChange,
  getOptionValue = defaultGetValue,
  getOptionLabel = defaultGetLabel,
  getOptionDescription = () => '',
  getSearchText,
  placeholder = 'Ketik untuk mencari...',
  emptyLabel = 'Data tidak ditemukan',
  disabled = false,
  loading = false,
  clearable = true,
  className = '',
}) {
  const generatedId = useId();
  const rootRef = useRef(null);
  const inputRef = useRef(null);
  const [open, setOpen] = useState(false);
  const [inputValue, setInputValue] = useState('');
  const [activeIndex, setActiveIndex] = useState(0);

  const selectedOption = useMemo(() => (
    options.find(option => String(getOptionValue(option)) === String(value)) || null
  ), [getOptionValue, options, value]);

  const selectedLabel = selectedOption ? getOptionLabel(selectedOption) : '';

  const filteredOptions = useMemo(() => {
    const query = normalizeSearch(inputValue);
    if (!query) return options;

    return options.filter(option => {
      const text = getSearchText
        ? getSearchText(option)
        : `${getOptionLabel(option)} ${getOptionDescription(option)}`;
      return normalizeSearch(text).includes(query);
    });
  }, [getOptionDescription, getOptionLabel, getSearchText, inputValue, options]);
  const safeActiveIndex = filteredOptions.length === 0
    ? 0
    : Math.min(activeIndex, filteredOptions.length - 1);

  useEffect(() => {
    function handlePointerDown(event) {
      if (!rootRef.current?.contains(event.target)) {
        setOpen(false);
      }
    }

    document.addEventListener('mousedown', handlePointerDown);
    return () => document.removeEventListener('mousedown', handlePointerDown);
  }, []);

  function openPicker() {
    if (disabled) return;
    setOpen(true);
    setInputValue('');
    setActiveIndex(0);
  }

  function closeIfFocusLeaves() {
    window.setTimeout(() => {
      if (!rootRef.current?.contains(document.activeElement)) {
        setOpen(false);
      }
    }, 0);
  }

  function selectOption(option) {
    const nextValue = getOptionValue(option);
    onChange?.(nextValue, option);
    setInputValue(getOptionLabel(option));
    setOpen(false);
    inputRef.current?.focus();
  }

  function clearSelection(event) {
    event.preventDefault();
    event.stopPropagation();
    onChange?.('', null);
    setInputValue('');
    setActiveIndex(0);
    setOpen(false);
    inputRef.current?.focus();
  }

  function handleKeyDown(event) {
    if (disabled) return;

    if (event.key === 'ArrowDown') {
      event.preventDefault();
      if (!open) {
        openPicker();
        return;
      }
      if (filteredOptions.length === 0) return;
      setActiveIndex(index => Math.min(index + 1, filteredOptions.length - 1));
    }

    if (event.key === 'ArrowUp') {
      event.preventDefault();
      if (filteredOptions.length === 0) return;
      setActiveIndex(index => Math.max(index - 1, 0));
    }

    if (event.key === 'Enter' && open) {
      event.preventDefault();
      const option = filteredOptions[safeActiveIndex];
      if (option) selectOption(option);
    }

    if (event.key === 'Escape') {
      event.preventDefault();
      setOpen(false);
    }
  }

  return (
    <div
      ref={rootRef}
      className={`searchable-combobox ${open ? 'is-open' : ''} ${disabled ? 'is-disabled' : ''} ${className}`}
      onBlur={closeIfFocusLeaves}
    >
      <div className="searchable-combobox-control" onClick={() => inputRef.current?.focus()}>
        <Search className="searchable-combobox-search" size={16} aria-hidden="true" />
        <input
          ref={inputRef}
          className="searchable-combobox-input"
          value={open ? inputValue : selectedLabel}
          placeholder={loading ? 'Memuat data...' : placeholder}
          disabled={disabled || loading}
          role="combobox"
          aria-autocomplete="list"
          aria-expanded={open}
          aria-controls={`${generatedId}-listbox`}
          aria-activedescendant={open ? `${generatedId}-option-${safeActiveIndex}` : undefined}
          onFocus={openPicker}
          onChange={(event) => {
            setInputValue(event.target.value);
            setOpen(true);
            setActiveIndex(0);
          }}
          onKeyDown={handleKeyDown}
        />
        <div className="searchable-combobox-actions">
          {clearable && value && !disabled && !loading && (
            <button
              type="button"
              className="searchable-combobox-button"
              title="Bersihkan pilihan"
              aria-label="Bersihkan pilihan"
              onMouseDown={event => event.preventDefault()}
              onClick={clearSelection}
            >
              <X size={16} />
            </button>
          )}
          <button
            type="button"
            className="searchable-combobox-button"
            title="Buka pilihan"
            aria-label="Buka pilihan"
            disabled={disabled || loading}
            onMouseDown={event => event.preventDefault()}
            onClick={() => {
              if (open) setOpen(false);
              else {
                openPicker();
                inputRef.current?.focus();
              }
            }}
          >
            <ChevronDown size={17} />
          </button>
        </div>
      </div>

      {open && !disabled && !loading && (
        <div id={`${generatedId}-listbox`} className="searchable-combobox-menu" role="listbox">
          {filteredOptions.length === 0 ? (
            <div className="searchable-combobox-empty">{emptyLabel}</div>
          ) : (
            filteredOptions.map((option, index) => {
              const optionValue = getOptionValue(option);
              const optionLabel = getOptionLabel(option);
              const description = getOptionDescription(option);
              const isSelected = String(optionValue) === String(value);

              return (
                <button
                  key={optionValue}
                  id={`${generatedId}-option-${index}`}
                  type="button"
                  role="option"
                  aria-selected={isSelected}
                  className={`searchable-combobox-option ${isSelected ? 'is-selected' : ''} ${safeActiveIndex === index ? 'is-active' : ''}`}
                  onMouseDown={event => event.preventDefault()}
                  onMouseEnter={() => setActiveIndex(index)}
                  onClick={() => selectOption(option)}
                >
                  <span className="searchable-combobox-option-label">{optionLabel}</span>
                  {description && (
                    <span className="searchable-combobox-option-description">{description}</span>
                  )}
                </button>
              );
            })
          )}
        </div>
      )}
    </div>
  );
}
