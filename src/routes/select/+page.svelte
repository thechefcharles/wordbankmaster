<script>
    import { goto } from '$app/navigation';
  
    // ✅ Must match Supabase exactly
    const categories = [
      'Movies & TV 🎬',
      'Pop Culture & Celebrities 🌟',
      'Food & Drink 🍔',
      'Slang & Sayings 🗣️',
      'History & Culture 🏛️',
      'Sports & Games 🏆'
    ];
  
    function selectCategory(category) {
      localStorage.setItem('selectedCategory', category);
      goto('/'); // go back to game
    }
  </script>
  
  <h2>Select a Category</h2>
  
  <div class="category-grid">
    {#each categories as cat}
      <button on:click={() => selectCategory(cat)}>{cat}</button>
    {/each}
  </div>
  
  <style>
    h2 {
      text-align: center;
      margin-top: 2rem;
      font-size: 2rem;
      color: limegreen;
    }
  
    .category-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
      gap: 1rem;
      padding: 2rem;
      justify-content: center;
    }
  
    button {
      padding: 1.25rem;
      font-size: 1.2rem;
      font-weight: bold;
      background-color: limegreen;
      border: none;
      border-radius: 12px;
      color: white;
      cursor: pointer;
      transition: background 0.2s ease;
    }
  
    button:hover {
      background-color: green;
    }
  </style>
  