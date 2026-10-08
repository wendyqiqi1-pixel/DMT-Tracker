// DMT Daily Tracker connection settings.
// Fill these in from Supabase → Project Settings → API.
// The anon (public) key is designed to be shipped to browsers: access to data is
// controlled by Microsoft sign-in plus the row-level security rules in supabase/schema.sql.
// Never put the service_role key here.
// Build DMT Daily Tracker as a standalone app with Microsoft sign-in
// While these still hold the placeholders, the app opens in demo mode with sample data.
window.DMT_CONFIG = {
  supabaseUrl: "https://YOUR-PROJECT.supabase.co",
  supabaseAnonKey: "YOUR-ANON-KEY"
};
