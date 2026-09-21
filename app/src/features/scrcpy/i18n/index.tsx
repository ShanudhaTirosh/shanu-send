import React, { createContext, useContext, ReactNode } from 'react';
import { en } from './locales/en';

const LanguageContext = createContext<{
  t: (path: string, params?: Record<string, string | number>) => string;
}>({
  t: (path: string) => path,
});

export const LanguageProvider: React.FC<{ children: ReactNode }> = ({ children }) => {
  const t = (path: string, params?: Record<string, string | number>): string => {
    const keys = path.split('.');
    let value: any = en;
    
    for (const k of keys) {
      if (value && typeof value === 'object' && k in value) {
        value = value[k];
      } else {
        return path;
      }
    }

    if (typeof value !== 'string') {
      return path;
    }

    let result = value;
    if (params) {
      Object.entries(params).forEach(([paramKey, paramVal]) => {
        result = result.replace(new RegExp(`\\{${paramKey}\\}`, 'g'), String(paramVal));
      });
    }

    return result;
  };

  return (
    <LanguageContext.Provider value={{ t }}>
      {children}
    </LanguageContext.Provider>
  );
};

export const useLanguage = () => useContext(LanguageContext);
