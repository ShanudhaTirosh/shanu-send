/** @type {import('tailwindcss').Config} */
export default {
  content: ["./index.html", "./src/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        // ShanuTechX brand palette — deep space background with electric
        // cyan/violet accents. Tuned for WCAG AA text contrast even inside
        // blurred glass panels (see frontend-design notes in the plan doc).
        void: {
          950: "#05060a",
          900: "#0a0d16",
          800: "#12162280",
        },
        neon: {
          cyan: "#4dd9ff",
          violet: "#9d7bff",
          pink: "#ff5fa8",
        },
      },
      backdropBlur: {
        glass: "18px",
      },
      boxShadow: {
        glass: "0 8px 32px rgba(0, 0, 0, 0.37)",
        glow: "0 0 24px rgba(77, 217, 255, 0.35)",
      },
      borderRadius: {
        glass: "20px",
      },
      keyframes: {
        radar: {
          "0%": { transform: "scale(0.6)", opacity: "0.6" },
          "100%": { transform: "scale(1.8)", opacity: "0" },
        },
      },
      animation: {
        radar: "radar 2.4s ease-out infinite",
      },
    },
  },
  plugins: [],
};
