<?php

return [
    'model' => env('OLLAMA_MODEL', 'llama3.2:3b'),        // ← Changed to lighter model

    'url' => env('OLLAMA_URL', 'http://127.0.0.1:11434'),

    'default_prompt' => env('OLLAMA_DEFAULT_PROMPT', 'Hello, how can I assist you today?'),

    /*
    |--------------------------------------------------------------------------
    | Keep Alive Duration
    |--------------------------------------------------------------------------
    |
    | How long the model stays loaded in memory.
    | '5m' = 5 minutes, '1h' = 1 hour, null = use Ollama default
    |
    */
    'keep_alive' => env('OLLAMA_KEEP_ALIVE', '10m'),     // Keep model loaded 10 minutes

    'connection' => [
        'timeout' => env('OLLAMA_CONNECTION_TIMEOUT', 300),
    ],

    'headers' => [
        'Authorization' => 'Bearer ' . env('OLLAMA_API_KEY'),
    ],
];
