// src/lib/supabase.js
import { createClient } from '@supabase/supabase-js';

const supabaseUrl = "https://heckmdvnetatqgnsdtoz.supabase.co";
const supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhlY2ttZHZuZXRhdHFnbnNkdG96Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Mzk4MzQwMjgsImV4cCI6MjA1NTQxMDAyOH0._z13upotSEsDCpZ1LCcPlthl2CXW68wbyLIq-LtVZyU";

export const supabase = createClient(supabaseUrl, supabaseAnonKey);
