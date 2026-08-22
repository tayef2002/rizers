// Server-side proxy for Groq API calls (Hadi AI Partner + Rizers AI Core voice intent).
// The Groq key lives only in this function's environment (GROQ_API_KEY secret) — it never
// reaches the browser. Callers must present a valid Supabase user JWT; unauthenticated
// requests are rejected so this can't be used as an open Groq relay.
import { createClient } from 'jsr:@supabase/supabase-js@2'

const GROQ_API_KEY = Deno.env.get('GROQ_API_KEY')!
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!

const ALLOWED_PATHS = new Set(['chat/completions', 'audio/transcriptions'])

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-groq-path',
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  const authHeader = req.headers.get('Authorization')
  if (!authHeader) {
    return new Response(JSON.stringify({ error: 'missing auth' }), { status: 401, headers: corsHeaders })
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
  })
  const { data: { user }, error } = await supabase.auth.getUser()
  if (error || !user) {
    return new Response(JSON.stringify({ error: 'unauthorized' }), { status: 401, headers: corsHeaders })
  }

  const groqPath = req.headers.get('x-groq-path') || 'chat/completions'
  if (!ALLOWED_PATHS.has(groqPath)) {
    return new Response(JSON.stringify({ error: 'unsupported path' }), { status: 400, headers: corsHeaders })
  }

  const contentType = req.headers.get('content-type') || ''
  let body: BodyInit
  const forwardHeaders: Record<string, string> = { Authorization: `Bearer ${GROQ_API_KEY}` }

  if (contentType.includes('multipart/form-data')) {
    // Let fetch set its own multipart boundary — don't set Content-Type manually here.
    body = await req.formData()
  } else {
    forwardHeaders['Content-Type'] = 'application/json'
    body = await req.text()
  }

  const groqRes = await fetch(`https://api.groq.com/openai/v1/${groqPath}`, {
    method: 'POST',
    headers: forwardHeaders,
    body,
  })

  const respBody = await groqRes.text()
  return new Response(respBody, {
    status: groqRes.status,
    headers: { ...corsHeaders, 'Content-Type': groqRes.headers.get('content-type') || 'application/json' },
  })
})
