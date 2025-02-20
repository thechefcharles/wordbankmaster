<script>
    export let digit = 0;  
    // The currently displayed digit
    let currentDigit = digit;
    // Adjust the height per digit (e.g., 40px)
    const digitHeight = 40;
    // Inline style for the reel container based on the current digit
    let reelStyle = `transform: translateY(-${currentDigit * digitHeight}px);`;
    
    // Watch for changes to the digit
    $: if (digit !== currentDigit) {
      const fullReelHeight = 10 * digitHeight;
      const targetOffset = 2 * fullReelHeight + (digit * digitHeight);
      reelStyle = `transform: translateY(-${targetOffset}px); transition: transform 0.8s cubic-bezier(0.68, -0.55, 0.265, 1.55);`;
      setTimeout(() => {
        currentDigit = digit;
        reelStyle = `transform: translateY(-${digit * digitHeight}px); transition: none;`;
      }, 800);
    }
  </script>
  
  <div class="slot-container">
    <div class="reel" style={reelStyle}>
      {#each Array(20) as _, i}
        <!-- i % 10 gives us a repeating sequence of digits -->
        <div class="slot-digit">{i % 10}</div>
      {/each}
    </div>
  </div>
  
  <style>
    /* Container is sized for a single digit */
    .slot-container {
      overflow: hidden;
      width: 30px;
      height: 40px;
    }
    .reel {
      display: flex;
      flex-direction: column;
    }
    .slot-digit {
      height: 40px;
      line-height: 40px;
      text-align: center;
      font-size: 1.2rem;
      font-family: 'Orbitron', sans-serif;
    }
  </style>
  