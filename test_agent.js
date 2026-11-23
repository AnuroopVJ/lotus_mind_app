// Terminal testing script for Lotusmind AI Agent
// Usage: node test_agent.js "Your prompt here"

const ENDPOINT = process.env.API_URL || 'https://lotusmind.vercel.app/api/chat';

async function main() {
  const prompt = process.argv[2] || 'Explain photosynthesis with a flowchart or ASCII diagram';
  console.log(`\n🤖 Sending prompt to Lotusmind Agent (${ENDPOINT}):\n\"${prompt}\"\n`);

  try {
    const res = await fetch(ENDPOINT, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        messages: [{ role: 'user', content: prompt }],
        mode: 'normal',
        stream: false,
      }),
    });

    const data = await res.json();
    console.log('📬 Response:\n');
    if (data.reply) {
      console.log(data.reply);
      if (data.model) console.log(`\n[Model: ${data.model}]`);
    } else {
      console.log(JSON.stringify(data, null, 2));
    }
  } catch (err) {
    console.error('❌ Error testing agent:', err);
  }
}

main();
