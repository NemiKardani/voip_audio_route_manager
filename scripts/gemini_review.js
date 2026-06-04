const fs = require('fs');

async function run() {
  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) {
    console.error("Error: GEMINI_API_KEY is not set.");
    process.exit(1);
  }

  const diffPath = process.argv[2];
  if (!diffPath || !fs.existsSync(diffPath)) {
    console.error("Error: Please provide a valid diff file path.");
    process.exit(1);
  }

  const diffContent = fs.readFileSync(diffPath, 'utf8');
  if (!diffContent.trim()) {
    console.log("No changes detected in diff.");
    return;
  }

  console.log(`Analyzing diff of size ${diffContent.length} bytes...`);

  const prompt = `You are an automated AI senior software engineer reviewing a pull request for the "voip_audio_route_manager" Dart/Flutter federated plugin.
Analyze the following git diff for:
1. Potential bugs, race conditions, edge cases, resource/memory leaks (e.g. Streams not canceled or AudioContext/HTMLMediaElements not cleaned up).
2. Proper implementation of APIs (especially W3C Audio Output Devices API, sink ID routing, permissions).
3. Code formatting, lints, and best practices.

Provide a highly constructive, structured code review in markdown. Start with a brief summary, then highlight key suggestions or bugs if any. Keep it actionable and concise.

Git Diff:
\`\`\`diff
${diffContent}
\`\`\`
`;

  try {
    const response = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${apiKey}`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          contents: [{
            parts: [{ text: prompt }]
          }]
        })
      }
    );

    if (!response.ok) {
      const errText = await response.text();
      throw new Error(`Gemini API error (${response.status}): ${errText}`);
    }

    const data = await response.json();
    const reviewText = data.candidates?.[0]?.content?.parts?.[0]?.text;
    
    if (!reviewText) {
      console.error("No response content from Gemini.");
      process.exit(1);
    }

    console.log("\n=== Gemini AI Code Review ===\n");
    console.log(reviewText);

    // Save to markdown for GitHub Action comments
    fs.writeFileSync('gemini_review.md', reviewText);
  } catch (error) {
    console.error("Error calling Gemini API:", error);
    // Write fallback content to avoid failing the workflow comment step
    fs.writeFileSync(
      'gemini_review.md', 
      `### ⚠️ Gemini AI Code Review Unavailable\n\nThe review service was temporarily unable to analyze this diff (e.g., rate limits or high service demand).\n\n**Details:** \`${error.message}\``
    );
    // Exit with 0 so the build process is not blocked by a third-party API outage
    process.exit(0);
  }
}

run();
