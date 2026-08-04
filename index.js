require("dotenv").config();
const noblox = require("noblox.js");
const OpenAI = require("openai");

const openai = new OpenAI({
  apiKey: process.env.AI_API_KEY, // 在 .env 填入 AI_API_KEY=sk-xxxxx
});

const MY_PLAYER_ID = parseInt(process.env.MY_PLAYER_ID, 10); // 你的主帳號 User ID
const BOT_NAME = process.env.BOT_NAME || "Bot"; // 機器人名字，用於關鍵字觸發

let lastId = 0;

async function login() {
  await noblox.setCookie(process.env.ROBLOX_COOKIE); // 在 .env 填入 ROBLOX_COOKIE=你的 cookie
  const current = await noblox.getCurrentUser();
  console.log(`[Bot] 登入成功: ${current.UserName} (${current.UserID})`);
}

async function fetchAndReply() {
  try {
    const messages = await noblox.getMessages({ pageNumber: 1, pageSize: 10 });

    if (!messages || !messages.length) return;

    for (const msg of messages) {
      if (msg.id <= lastId) continue;
      lastId = Math.max(lastId, msg.id);

      // 只處理私訊，忽略系統通知
      if (msg.messageType !== "PrivateMessage" && msg.messageType !== "Inbox") continue;

      const senderId = msg.sender.userId;
      const content = msg.body;

      // 過濾條件：只有 MY_PLAYER_ID 或訊息包含機器人名稱才回覆
      if (senderId !== MY_PLAYER_ID && !content.toLowerCase().includes(BOT_NAME.toLowerCase())) {
        continue;
      }

      console.log(`[Chat] 來自 ${msg.sender.username}: ${content}`);

      // AI 思考
      const reply = await think(content);
      console.log(`[AI] 回覆: ${reply}`);

      // 發送回覆
      await noblox.sendPrivateMessage(senderId, reply);
      console.log(`[Bot] 已回覆給 ${msg.sender.username}`);
    }
  } catch (err) {
    console.error(`[Error] ${err.message}`);
    // AI 網路塞車或 API 額度用完時不會讓整個機器人斷線
  }
}

async function think(userMessage) {
  const res = await openai.chat.completions.create({
    model: "gpt-4",
    messages: [
      {
        role: "system",
        content:
          "你是一個正在和玩家一邊玩 Roblox、一邊聊天的真實玩家。講話要輕鬆、口語、字數不要太多，像個真正的遊戲夥伴。使用繁體中文回覆。",
      },
      { role: "user", content: userMessage },
    ],
  });
  return res.choices[0].text?.trim() || res.choices[0].message?.content?.trim() || "...";
}

async function main() {
  await login();

  // 每隔 30 秒檢查一次
  setInterval(fetchAndReply, 30_000);
  console.log("[Bot] 開始監聽私訊...");
}

main();
