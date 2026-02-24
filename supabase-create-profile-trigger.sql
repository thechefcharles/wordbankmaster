-- Run this in Supabase SQL Editor (Dashboard → SQL Editor) to auto-create profiles for new users.
-- Fixes: "Profile failed to load or create" for new signups in Chrome.

-- 1. Create or replace the trigger function
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, arcade_bankroll)
  VALUES (NEW.id, 1000)
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. Drop existing trigger if it exists (to avoid duplicates)
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- 3. Create trigger to run on new user signup
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

-- 4. RLS: Allow users to insert their own profile (fixes "new row violates row-level security policy")
DROP POLICY IF EXISTS "Users can insert own profile" ON public.profiles;
CREATE POLICY "Users can insert own profile"
  ON public.profiles FOR INSERT
  WITH CHECK (auth.uid() = id);

-- Note: If your profiles table has different columns, edit the INSERT above.
