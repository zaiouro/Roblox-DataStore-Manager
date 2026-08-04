require('dotenv').config();
const fs = require('fs');
const path = require('path');
const { Client, GatewayIntentBits, EmbedBuilder, SlashCommandBuilder, Routes, REST, GuildVerificationLevel, Partials } = require('discord.js');

const LEVELS_FILE = path.join(__dirname, 'levels.json');
const CONFIG_FILE = path.join(__dirname, 'config.json');
const lastXpAt = new Map();
const lastAttackAt = new Map();

const DEFAULT_CONFIG = {
  xp: {
    cooldownMs: 60000,
    base: 10,
    lengthDivisor: 50,
    maxLengthBonus: 20,
    curveDivisor: 50,
    multiplier: 1,
    boostRoles: {}
  },
  daily: {
    base: 50,
    perStreak: 10,
    cap: 150
  },
  attack: {
    cooldownMs: 300000,
    diceMax: 100,
    normMin: 5,
    normMax: 15,
    minLevel: 1,
    protectBelow: 2,
    levelGap: 0
  },
  levelup: {
    enabled: true,
    channelId: null
  },
  starboard: {
    enabled: true,
    channelId: null,
    threshold: 3,
    emoji: '⭐'
  },
  email: {
    channelId: null
  },
  antiRaid: {
    enabled: true,
    alertChannelId: null,
    alertRoleId: null,
    burst: {
      enabled: true,
      maxJoins: 5,
      windowMs: 30000,
      lockdownMs: 600000
    },
    newAccount: {
      enabled: true,
      minAgeDays: 7,
      kick: true
    },
    spam: {
      enabled: true,
      maxMessages: 5,
      windowMs: 3000,
      muteMs: 60000
    }
  },
  roles: {}
};

function deepMerge(base, extra) {
  const out = { ...base };
  for (const [k, v] of Object.entries(extra || {})) {
    if (v && typeof v === 'object' && !Array.isArray(v) && base[k] && typeof base[k] === 'object') {
      out[k] = deepMerge(base[k], v);
    } else {
      out[k] = v;
    }
  }
  return out;
}

function loadConfig() {
  if (!fs.existsSync(CONFIG_FILE)) return structuredClone(DEFAULT_CONFIG);
  try {
    return deepMerge(DEFAULT_CONFIG, JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf8')));
  } catch {
    return structuredClone(DEFAULT_CONFIG);
  }
}

function saveConfig() {
  fs.writeFileSync(CONFIG_FILE, JSON.stringify(config, null, 2));
}

let config = loadConfig();

function getPath(obj, key) {
  return key.split('.').reduce((o, k) => (o == null ? undefined : o[k]), obj);
}

function setPath(obj, key, value) {
  const parts = key.split('.');
  let o = obj;
  for (let i = 0; i < parts.length - 1; i++) {
    if (o[parts[i]] == null) o[parts[i]] = {};
    o = o[parts[i]];
  }
  o[parts[parts.length - 1]] = value;
}

function todayStr() {
  const d = new Date();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${d.getFullYear()}-${m}-${day}`;
}

function daysAgo(dateStr) {
  const parts = dateStr.split('-');
  const then = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]));
  then.setHours(0, 0, 0, 0);
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  return Math.round((today - then) / 86400000);
}

function updateStreak(user) {
  const today = todayStr();
  const last = user.lastChatDate;
  if (!last) {
    user.streak = 1;
  } else if (daysAgo(last) === 1) {
    user.streak = (user.streak || 1) + 1;
  } else if (daysAgo(last) > 1) {
    user.streak = 1;
  }
  user.lastChatDate = today;
  return user.streak || 1;
}

function levelFromXp(xp) {
  return Math.floor(Math.sqrt(xp / config.xp.curveDivisor));
}

function xpForLevel(level) {
  return config.xp.curveDivisor * level * level;
}

function loadLevels() {
  if (!fs.existsSync(LEVELS_FILE)) return {};
  try {
    return JSON.parse(fs.readFileSync(LEVELS_FILE, 'utf8'));
  } catch {
    return {};
  }
}

function saveLevels(levels) {
  fs.writeFileSync(LEVELS_FILE, JSON.stringify(levels, null, 2));
}

async function userDisplayName(id) {
  try {
    const user = await client.users.fetch(id);
    return user.username;
  } catch {
    return `user_${id}`;
  }
}

async function syncLevelRoles(guild, memberId, level) {
  const roleEntries = Object.entries(config.roles).sort((a, b) => Number(a[0]) - Number(b[0]));
  if (roleEntries.length === 0) return;
  let member;
  try {
    member = await guild.members.fetch(memberId);
  } catch {
    return;
  }
  for (const [lv, roleId] of roleEntries) {
    const target = Number(lv);
    const has = member.roles.cache.has(String(roleId));
    try {
      if (level >= target && !has) {
        await member.roles.add(roleId);
      } else if (level < target && has) {
        await member.roles.remove(roleId);
      }
    } catch (ignored) {
    }
  }
}

function rankEmbed(target, user) {
  const currentXp = xpForLevel(user.level);
  const nextXp = xpForLevel(user.level + 1);
  const progress = nextXp <= currentXp ? 0 : Math.round(((user.xp - currentXp) / (nextXp - currentXp)) * 100);
  const filled = Math.round(progress / 10);
  const bar = '█'.repeat(filled) + '░'.repeat(10 - filled);
  const avatar = target.displayAvatarURL({ size: 256 });
  return new EmbedBuilder()
    .setColor(0x1a1a2e)
    .setAuthor({ name: target.username, iconURL: avatar })
    .setThumbnail(avatar)
    .addFields(
      { name: 'Level', value: `${user.level}`, inline: true },
      { name: 'XP', value: `${user.xp} XP`, inline: true },
      { name: 'Streak', value: `🔥 ${user.streak || 0} days`, inline: true },
      { name: 'Progress', value: `${bar} ${progress}%`, inline: false }
    )
    .setFooter({ text: 'Nora • Holloway' })
    .setTimestamp();
}

async function commandsChannel() {
  if (!COMMANDS_CHANNEL_ID) return null;
  try {
    return await client.channels.fetch(COMMANDS_CHANNEL_ID);
  } catch {
    return null;
  }
}

function xpMultiplierFor(member) {
  let mult = Number(config.xp.multiplier) || 1;
  if (!member) return mult;
  for (const [roleId, m] of Object.entries(config.xp.boostRoles || {})) {
    if (member.roles.cache.has(String(roleId))) {
      mult *= Number(m) || 1;
    }
  }
  return mult;
}

async function levelupChannel() {
  if (config.levelup.channelId) {
    try {
      const ch = await client.channels.fetch(String(config.levelup.channelId));
      if (ch) return ch;
    } catch (ignored) {
    }
  }
  return commandsChannel();
}

async function announceLevelup(channel, author, user, description) {
  if (config.levelup.enabled === false) return false;
  const ch = (await levelupChannel()) || channel;
  const embed = rankEmbed(author, user);
  if (description) embed.setDescription(description);
  await ch.send({ embeds: [embed] });
  return true;
}

function msgCtx(message, target) {
  return {
    author: message.author,
    member: message.member,
    guild: message.guild,
    channel: message.channel,
    target,
    role: message.mentions.roles.first(),
    chan: message.mentions.channels.first(),
    async send(text) { await message.channel.send(text); },
    async embed(embed) {
      const channel = (await commandsChannel()) || message.channel;
      await channel.send({ embeds: [embed] });
    },
    async embedHere(embed) {
      await message.channel.send({ embeds: [embed] });
    }
  };
}

function slashCtx(interaction) {
  return {
    author: interaction.user,
    member: interaction.member,
    guild: interaction.guild,
    channel: interaction.channel,
    target: interaction.options.getUser('user'),
    role: interaction.options.getRole('role'),
    chan: interaction.options.getChannel('channel'),
    async send(text) { await interaction.editReply(text); },
    async embed(embed) { await interaction.editReply({ embeds: [embed] }); },
    async embedHere(embed) { await interaction.editReply({ embeds: [embed] }); }
  };
}

async function cmdRank(ctx) {
  const target = ctx.target || ctx.author;
  const levels = loadLevels();
  const user = levels[target.id] || { xp: 0, level: 0 };
  await ctx.embed(rankEmbed(target, user));
}

async function cmdDaily(ctx) {
  const levels = loadLevels();
  const user = levels[ctx.author.id] || { xp: 0, level: 0, streak: 0 };
  const today = todayStr();
  if (user.lastDaily === today) {
    await ctx.send('You already claimed your daily reward today. Come back tomorrow!');
    return;
  }
  const streak = user.streak || 0;
  const reward = config.daily.base + Math.min(config.daily.cap, streak * config.daily.perStreak);
  user.xp += reward;
  user.lastDaily = today;
  const newLevel = levelFromXp(user.xp);
  if (newLevel > user.level) {
    user.level = newLevel;
    levels[ctx.author.id] = user;
    saveLevels(levels);
    const announced = await announceLevelup(ctx.channel, ctx.author, user, `☀️ Daily reward: +${reward} XP! 🔥 Streak: ${streak} days`);
    if (!announced) await ctx.send(`☀️ +${reward} XP daily reward claimed! You reached level **${newLevel}**! 🔥 Streak: ${streak} days`);
  } else {
    levels[ctx.author.id] = user;
    saveLevels(levels);
    await ctx.send(`☀️ +${reward} XP daily reward claimed! 🔥 Streak: ${streak} days (Total: ${user.xp} XP)`);
  }
}

async function cmdAttack(ctx) {
  const target = ctx.target;
  if (!target) {
    await ctx.send('Mention someone to attack: `?kill @user`');
    return;
  }
  if (target.id === ctx.author.id) {
    await ctx.send('You can\'t attack yourself. That would be strange.');
    return;
  }
  if (target.bot) {
    await ctx.send('You can\'t attack a bot.');
    return;
  }
  const now = Date.now();
  if (now - (lastAttackAt.get(ctx.author.id) || 0) < config.attack.cooldownMs) {
    await ctx.send('You\'re on cooldown. Wait a bit before attacking again.');
    return;
  }
  const levels = loadLevels();
  const attacker = levels[ctx.author.id] || { xp: 0, level: 0 };
  const victim = levels[target.id] || { xp: 0, level: 0 };
  if (attacker.level < config.attack.minLevel) {
    await ctx.send(`You need to reach **level ${config.attack.minLevel}** before you can attack anyone.`);
    return;
  }
  if (victim.level < config.attack.protectBelow) {
    await ctx.send(`<@${target.id}> is protected (below level ${config.attack.protectBelow}). Find another target.`);
    return;
  }
  if (config.attack.levelGap > 0 && Math.abs(attacker.level - victim.level) > config.attack.levelGap) {
    await ctx.send(`Level gap too large. You can only attack players within **${config.attack.levelGap}** levels of you.`);
    return;
  }
  if (victim.xp <= 0) {
    await ctx.send(`<@${target.id}> has no XP to steal. Find someone richer.`);
    return;
  }
  lastAttackAt.set(ctx.author.id, now);

  const a = config.attack;
  const roll = Math.floor(Math.random() * a.diceMax) + 1;
  let damage = a.normMin + Math.floor(Math.random() * (a.normMax - a.normMin + 1));
  damage = Math.min(damage, victim.xp);
  victim.xp -= damage;
  attacker.xp += damage;
  const victimOldLevel = victim.level;
  const attackerOldLevel = attacker.level;
  victim.level = levelFromXp(victim.xp);
  attacker.level = levelFromXp(attacker.xp);
  levels[target.id] = victim;
  levels[ctx.author.id] = attacker;
  saveLevels(levels);
  if (victim.level < victimOldLevel) {
    await syncLevelRoles(ctx.guild, target.id, victim.level);
  }
  if (attacker.level > attackerOldLevel) {
    await syncLevelRoles(ctx.guild, ctx.author.id, attacker.level);
  }
  await ctx.send(`🎲 Rolled **${roll} / ${a.diceMax}** — <@${target.id}> lost **${damage} XP**.\n<@${ctx.author.id}> gained **${damage} XP**.`);
}

async function cmdLeaderboard(ctx) {
  const levels = loadLevels();
  const sorted = Object.entries(levels).sort((a, b) => b[1].xp - a[1].xp).slice(0, 10);
  if (sorted.length === 0) {
    await ctx.send('No XP yet. Start chatting!');
    return;
  }
  const lines = [];
  for (let i = 0; i < sorted.length; i++) {
    const [id, data] = sorted[i];
    const name = await userDisplayName(id);
    lines.push(`${i + 1}. **${name}** — Level ${data.level} (${data.xp} XP)`);
  }
  await ctx.send(`🏆 **Leaderboard**\n${lines.join('\n')}`);
}

async function cmdHelp(ctx) {
  const embed = new EmbedBuilder()
    .setColor(0x1a1a2e)
    .setTitle('📜 Nora • Holloway Bot Commands')
    .setDescription([
      '**Slash commands**',
      '`/rank` — level card',
      '`/leaderboard` — top 10',
      '`/daily` — claim daily XP',
      '`/attack @user` — RP attack',
      '`/config` — view settings (admin)',
      '`/config-set` / `/config-role` / `/config-boost` / `/config-channel`',
      '',
      '**Prefix commands (still work)**',
      '`?rank` / `?level`',
      '`?leaderboard` / `?lb`',
      '`?daily`',
      '`?kill @user` / `?attack`',
      '`?config` / `?config set <key> <value>`',
      '`?config role <level> @role`',
      '`?config boost @role <mult>`',
      '`?config channel <#ch>`',
      '`?config starboard <#ch>` — starboard channel',
      '`?config set starboard.* <value>` — starboard settings',
      '`?config set antiRaid.* <value>` — anti-raid settings',
      '`?email @user <subject> || <body>` — send a facility email (admin)',
      '`?config email <#ch>` — set email delivery channel',
      '`?help` — this list'
    ].join('\n'))
    .setFooter({ text: 'Nora • Holloway' });
  await ctx.embedHere(embed);
}

async function cmdConfig(ctx, sub, args) {
  const canManage = ctx.member && ctx.member.permissions.has('ManageGuild');
  if (!canManage) {
    await ctx.send('Only server admins (Manage Server permission) can use ?config.');
    return;
  }
  if (!sub || sub === 'show') {
    let desc = [
      '**XP**',
      `cooldownMs = ${config.xp.cooldownMs}`,
      `base = ${config.xp.base}`,
      `lengthDivisor = ${config.xp.lengthDivisor}`,
      `maxLengthBonus = ${config.xp.maxLengthBonus}`,
      `curveDivisor = ${config.xp.curveDivisor}`,
      `multiplier = ${config.xp.multiplier}`,
      '',
      '**Daily**',
      `base = ${config.daily.base}`,
      `perStreak = ${config.daily.perStreak}`,
      `cap = ${config.daily.cap}`,
      '',
      '**Attack**',
      `cooldownMs = ${config.attack.cooldownMs}`,
      `diceMax = ${config.attack.diceMax}`,
      `damage = ${config.attack.normMin}-${config.attack.normMax}`,
      `minLevel = ${config.attack.minLevel}`,
      `protectBelow = ${config.attack.protectBelow}`,
      `levelGap = ${config.attack.levelGap}`,
      '',
      '**Level-Up**',
      `enabled = ${config.levelup.enabled}`,
      `channelId = ${config.levelup.channelId || '(commands channel)'}`,
      '',
      '**Starboard**',
      `enabled = ${config.starboard.enabled}`,
      `emoji = ${config.starboard.emoji}`,
      `threshold = ${config.starboard.threshold} ${config.starboard.emoji}`,
      `channelId = ${config.starboard.channelId ? `<#${config.starboard.channelId}>` : '(commands channel)'}`,
      '',
      '**Email**',
      `channelId = ${config.email.channelId ? `<#${config.email.channelId}>` : '(commands channel)'}`,
      '',
      '**Anti-Raid**',
      `enabled = ${config.antiRaid.enabled}`,
      `burst = ${config.antiRaid.burst.maxJoins} joins / ${config.antiRaid.burst.windowMs / 1000}s (lockdown ${config.antiRaid.burst.lockdownMs / 60000} min)`,
      `newAccount = ${config.antiRaid.newAccount.minAgeDays} days (kick: ${config.antiRaid.newAccount.kick})`,
      `spam = ${config.antiRaid.spam.maxMessages} msgs / ${config.antiRaid.spam.windowMs / 1000}s (mute ${config.antiRaid.spam.muteMs / 60000} min)`,
      `alertChannel = ${config.antiRaid.alertChannelId || '(commands channel)'}`,
      `alertRole = ${config.antiRaid.alertRoleId ? `<@&${config.antiRaid.alertRoleId}>` : '(none)'}`,
      '',
      '**Roles**'
    ].join('\n');
    const roleEntries = Object.entries(config.roles).sort((a, b) => Number(a[0]) - Number(b[0]));
    if (roleEntries.length === 0) {
      desc += '\n(no level roles configured)';
    } else {
      for (const [lv, roleId] of roleEntries) {
        desc += `\nLevel ${lv} → <@&${roleId}>`;
      }
    }
    const boostEntries = Object.entries(config.xp.boostRoles || {});
    desc += '\n**XP Boost Roles**';
    if (boostEntries.length === 0) {
      desc += '\n(no XP boost roles configured)';
    } else {
      for (const [roleId, m] of boostEntries) {
        desc += `\n<@&${roleId}> ×${m} XP`;
      }
    }
    const embed = new EmbedBuilder()
      .setColor(0x1a1a2e)
      .setTitle('⚙️ Bot Config')
      .setDescription(desc)
      .setFooter({ text: 'Use /config-set or ?config set <key> <value> to change' })
      .setTimestamp();
    await ctx.embed(embed);
    return;
  }

  if (sub === 'set') {
    const key = args[1];
    const value = args[2];
    if (!key || value === undefined) {
      await ctx.send('Usage: `?config set <key> <value>`');
      return;
    }
    if (key.startsWith('roles')) {
      await ctx.send('Use `?config role <level> @role` for roles.');
      return;
    }
    const current = getPath(config, key);
    if (current === undefined) {
      await ctx.send(`Unknown config key \`${key}\`. See ?config.`);
      return;
    }
    if (current !== null && typeof current === 'object') {
      await ctx.send(`\`${key}\` is a group. Use \`?config role\` or \`?config boost\` for its entries.`);
      return;
    }
    let parsed = value;
    if (typeof current === 'number') {
      parsed = Number(value);
      if (Number.isNaN(parsed)) {
        await ctx.send(`\`${value}\` is not a number.`);
        return;
      }
    } else if (typeof current === 'boolean') {
      parsed = value.toLowerCase() === 'true';
    }
    setPath(config, key, parsed);
    saveConfig();
    await ctx.send(`✅ Set \`${key}\` = \`${String(parsed)}\``);
    return;
  }

  if (sub === 'role') {
    const level = Number(args[1]);
    if (!Number.isInteger(level) || level < 1) {
      await ctx.send('Usage: `?config role <level> @role`');
      return;
    }
    const role = ctx.role;
    if (role) {
      config.roles[String(level)] = role.id;
      saveConfig();
      await ctx.send(`✅ Level ${level} now awards <@&${role.id}>`);
      return;
    }
    if (config.roles[String(level)]) {
      const removed = config.roles[String(level)];
      delete config.roles[String(level)];
      saveConfig();
      await ctx.send(`✅ Removed role <@&${removed}> from level ${level}`);
      return;
    }
    await ctx.send('Mention a role: `?config role 5 @RoleName`');
    return;
  }

  if (sub === 'boost') {
    const role = ctx.role;
    const mult = Number(args[2]);
    if (role && Number.isFinite(mult) && mult > 0) {
      config.xp.boostRoles[role.id] = mult;
      saveConfig();
      await ctx.send(`✅ <@&${role.id}> now earns **×${mult}** XP.`);
      return;
    }
    if (role && config.xp.boostRoles[role.id] !== undefined) {
      const removed = config.xp.boostRoles[role.id];
      delete config.xp.boostRoles[role.id];
      saveConfig();
      await ctx.send(`✅ Removed XP boost (×${removed}) from <@&${role.id}>.`);
      return;
    }
    await ctx.send('Usage: `?config boost @Role <multiplier>` (mention a role with no number to remove)');
    return;
  }

  if (sub === 'channel') {
    const ch = ctx.chan;
    if (ch) {
      config.levelup.channelId = ch.id;
      saveConfig();
      await ctx.send(`✅ Level-up announcements will go to <#${ch.id}>.`);
      return;
    }
    if (args[1] && args[1].toLowerCase() === 'none') {
      config.levelup.channelId = null;
      saveConfig();
      await ctx.send('✅ Level-up announcements will use the commands channel (or message channel).');
      return;
    }
    await ctx.send('Usage: `?config channel <#channel>` or `?config channel none`');
    return;
  }

  if (sub === 'starboard') {
    const ch = ctx.chan;
    if (ch) {
      config.starboard.channelId = ch.id;
      saveConfig();
      await ctx.send(`✅ Starboard posts will go to <#${ch.id}>.`);
      return;
    }
    if (args[1] && args[1].toLowerCase() === 'none') {
      config.starboard.channelId = null;
      saveConfig();
      await ctx.send('✅ Starboard will use the commands channel.');
      return;
    }
    await ctx.send('Usage: `?config starboard <#channel>` or `?config starboard none`');
    return;
  }

  if (sub === 'email') {
    const ch = ctx.chan;
    if (ch) {
      config.email.channelId = ch.id;
      saveConfig();
      await ctx.send(`✅ Facility emails will be delivered to <#${ch.id}>.`);
      return;
    }
    if (args[1] && args[1].toLowerCase() === 'none') {
      config.email.channelId = null;
      saveConfig();
      await ctx.send('✅ Facility emails will use the commands channel.');
      return;
    }
    await ctx.send('Usage: `?config email <#channel>` or `?config email none`');
    return;
  }
}

async function emailChannel() {
  if (config.email.channelId) {
    try {
      const ch = await client.channels.fetch(String(config.email.channelId));
      if (ch) return ch;
    } catch (ignored) {
    }
  }
  return commandsChannel();
}

// Build a lore email embed (in-facility letter style)
function emailEmbed({ fromName, fromAddress, toName, toAddress, subject, body, signature }) {
  const lines = (body || '').split('\n').map((l) => l.trim()).filter(Boolean);
  const parts = ['**Subject:** ' + (subject || '(no subject)'), '', '> ' + lines.join('\n> ') || '*…*'];
  if (signature) parts.push('', '— *' + signature + '*');
  const desc = parts.join('\n');
  return new EmbedBuilder()
    .setColor(0x1a1a2e)
    .setAuthor({ name: '📧 Hadasphere Facility Mail', iconURL: client.user.displayAvatarURL({ size: 64 }) })
    .addFields(
      { name: 'From', value: `**${fromName || 'Hadasphere'}**\n<${fromAddress || 'noreply@hadasphere.facility'}>`, inline: true },
      { name: 'To', value: `**${toName || 'All Personnel'}**\n<${toAddress || 'personnel@hadasphere.facility'}>`, inline: true },
      { name: 'Sent', value: `<t:${Math.floor(Date.now() / 1000)}:F>`, inline: false }
    )
    .setDescription(desc)
    .setFooter({ text: 'Facility internal correspondence • Do not forward' })
    .setTimestamp();
}

async function cmdEmail(ctx, args) {
  const canManage = ctx.member && ctx.member.permissions.has('ManageGuild');
  if (!canManage) {
    await ctx.send('Only server admins (Manage Server permission) can send facility emails.');
    return;
  }
  const target = ctx.target;
  const rest = args.join(' ').trim();
  if (!target || !rest) {
    await ctx.send('Usage: `?email @user <subject> || <body>` or `/email user:<@user> subject:<...> body:<...>`');
    return;
  }
  let subject = rest;
  let body = '';
  const sep = rest.indexOf('||');
  if (sep >= 0) {
    subject = rest.slice(0, sep).trim();
    body = rest.slice(sep + 2).trim();
  }
  const embed = emailEmbed({
    toName: target.username,
    toAddress: `${target.username.toLowerCase().replace(/[^a-z0-9]+/g, '.')}@personnel.hadasphere.facility`,
    subject,
    body
  });

  // 1) DM the recipient (works even outside the server / with DMs open)
  let dmOk = false;
  try {
    const dm = await target.createDM();
    await dm.send({ embeds: [embed] });
    dmOk = true;
  } catch (err) {
    console.error('Email DM failed for', target.username + ':', err.message);
  }

  // 2) Log the email to the configured channel too
  const ch = await emailChannel();
  let logOk = false;
  if (ch) {
    try {
      await ch.send({ embeds: [embed], content: target ? `<@${target.id}>` : undefined });
      logOk = true;
    } catch (err) {
      console.error('Email channel post failed:', err.message);
    }
  }

  if (dmOk) {
    await ctx.send(`📧 Email delivered to **${target.username}** via DM${logOk ? ' and logged to <#' + ch.id + '>' : ''}.`);
  } else if (logOk) {
    await ctx.send(`📧 Email posted to <#${ch.id}> but **${target.username}** has DMs closed — they will only see it in the channel.`);
  } else {
    await ctx.send('⚠️ Email could not be delivered. DMs are closed and no email channel is configured. Use `?config email <#channel>`.');
  }
}

async function handleCommand(ctx, cmd, args) {
  if (cmd === 'rank' || cmd === 'level') return cmdRank(ctx);
  if (cmd === 'daily') return cmdDaily(ctx);
  if (cmd === 'kill' || cmd === 'attack') return cmdAttack(ctx);
  if (cmd === 'leaderboard' || cmd === 'lb') return cmdLeaderboard(ctx);
  if (cmd === 'config') return cmdConfig(ctx, args[0], args);
  if (cmd === 'email') return cmdEmail(ctx, args);
  if (cmd === 'help') return cmdHelp(ctx);
}

const CHANNEL_ID = process.env.CHANNEL_ID;
const COMMANDS_CHANNEL_ID = process.env.COMMANDS_CHANNEL_ID;
const SITE_DIR = process.env.SITE_DIR;
const DEVLOG_FILE = path.join(SITE_DIR || __dirname, 'devlog.json');

const STATUS_PREFIX = {
  '[NEW]': 'new',
  '[WIP]': 'wip',
  '[DONE]': 'done',
  '[DRAFT]': 'draft'
};

const SERVER_MEMBERS_INTENT = process.env.ENABLE_SERVER_MEMBERS_INTENT === 'true';

const client = new Client({
  partials: [Partials.Message, Partials.Channel, Partials.Reaction],
  intents: [
    GatewayIntentBits.Guilds,
    GatewayIntentBits.GuildMessages,
    GatewayIntentBits.MessageContent,
    GatewayIntentBits.GuildMessageReactions
  ].concat(SERVER_MEMBERS_INTENT ? [GatewayIntentBits.GuildMembers] : [])
});

function readLocalDevlog() {
  if (!fs.existsSync(DEVLOG_FILE)) return [];
  return JSON.parse(fs.readFileSync(DEVLOG_FILE, 'utf8'));
}

function writeLocalDevlog(entries) {
  fs.writeFileSync(DEVLOG_FILE, JSON.stringify(entries, null, 2));
}

async function deploySite() {
  if (!SITE_DIR) return;
  const { exec } = require('child_process');
  await new Promise((resolve) => {
    exec('vercel deploy --prod', { cwd: SITE_DIR, windowsHide: true }, (err, stdout, stderr) => {
      if (err) {
        console.error('Vercel deploy failed:', stderr || err.message);
      } else {
        console.log('Vercel deploy output:', stdout.split('\n').slice(-3).join('\n'));
      }
      resolve();
    });
  });
}

async function getDevlog() {
  return readLocalDevlog();
}

async function pushDevlog(entries) {
  writeLocalDevlog(entries);
  await deploySite();
}

const slashCommands = [
  new SlashCommandBuilder()
    .setName('rank')
    .setDescription('Show your level card')
    .addUserOption((o) => o.setName('user').setDescription('User to check').setRequired(false)),
  new SlashCommandBuilder()
    .setName('leaderboard')
    .setDescription('Top 10 XP leaderboard'),
  new SlashCommandBuilder()
    .setName('daily')
    .setDescription('Claim your daily XP reward'),
  new SlashCommandBuilder()
    .setName('attack')
    .setDescription('Attack a user and steal their XP')
    .addUserOption((o) => o.setName('user').setDescription('Who to attack').setRequired(true)),
  new SlashCommandBuilder()
    .setName('help')
    .setDescription('Show all bot commands'),
  new SlashCommandBuilder()
    .setName('config')
    .setDescription('View bot settings (admin)'),
  new SlashCommandBuilder()
    .setName('config-set')
    .setDescription('Change a config value (admin)')
    .addStringOption((o) => o.setName('key').setDescription('Config key').setRequired(true))
    .addStringOption((o) => o.setName('value').setDescription('New value').setRequired(true)),
  new SlashCommandBuilder()
    .setName('config-role')
    .setDescription('Set/remove the role awarded at a level (admin)')
    .addIntegerOption((o) => o.setName('level').setDescription('Level number').setRequired(true))
    .addRoleOption((o) => o.setName('role').setDescription('Role to award (omit to remove)').setRequired(false)),
  new SlashCommandBuilder()
    .setName('config-boost')
    .setDescription('Set/remove an XP boost role (admin)')
    .addRoleOption((o) => o.setName('role').setDescription('Role to boost').setRequired(true))
    .addNumberOption((o) => o.setName('multiplier').setDescription('XP multiplier, e.g. 2 for x2 (omit to remove)').setRequired(false)),
  new SlashCommandBuilder()
    .setName('config-channel')
    .setDescription('Set the level-up announcement channel (admin)')
    .addChannelOption((o) => o.setName('channel').setDescription('Channel to announce in (omit to reset)').setRequired(false)),
  new SlashCommandBuilder()
    .setName('email')
    .setDescription('Send a Hadasphere facility email to a player (admin)')
    .addUserOption((o) => o.setName('user').setDescription('Recipient').setRequired(true))
    .addStringOption((o) => o.setName('subject').setDescription('Email subject').setRequired(true))
    .addStringOption((o) => o.setName('body').setDescription('Email body (lore)').setRequired(true))
];

async function registerCommands() {
  const body = slashCommands.map((c) => c.toJSON());
  const rest = new REST({ version: '10' }).setToken(process.env.BOT_TOKEN);
  try {
    if (process.env.GUILD_ID) {
      await rest.put(Routes.applicationGuildCommands(client.user.id, process.env.GUILD_ID), { body });
      console.log(`Registered ${body.length} slash commands for guild ${process.env.GUILD_ID}`);
    } else {
      await rest.put(Routes.applicationCommands(client.user.id), { body });
      console.log(`Registered ${body.length} global slash commands (may take up to 1 hour to appear)`);
    }
  } catch (err) {
    console.error('Failed to register slash commands:', err);
  }
}

client.once('ready', () => {
  console.log(`Logged in as ${client.user.tag}`);
  if (!CHANNEL_ID) console.warn('CHANNEL_ID is not set in .env');
  if ((config.antiRaid.newAccount.enabled || config.antiRaid.burst.enabled) && !SERVER_MEMBERS_INTENT) {
    console.warn('Anti-raid join detection is OFF: set ENABLE_SERVER_MEMBERS_INTENT=true in .env AND enable "Server Members Intent" in the Discord Developer Portal (Privileged Gateway Intents).');
  }
  registerCommands();
});

client.on('interactionCreate', async (interaction) => {
  if (interaction.isChatInputCommand()) {
    const adminCommands = new Set(['config', 'config-set', 'config-role', 'config-boost', 'config-channel', 'email']);
    await interaction.deferReply(adminCommands.has(interaction.commandName) ? { ephemeral: true } : {});
    const ctx = slashCtx(interaction);
    const name = interaction.commandName;
    let cmd = name;
    let args = [];
    if (name === 'config-set') {
      cmd = 'config';
      args = ['set', interaction.options.getString('key'), interaction.options.getString('value')];
    } else if (name === 'config-role') {
      cmd = 'config';
      args = ['role', String(interaction.options.getInteger('level'))];
    } else if (name === 'config-boost') {
      cmd = 'config';
      const mult = interaction.options.getNumber('multiplier');
      args = ['boost', 'role', mult == null ? '' : String(mult)];
    } else if (name === 'config-channel') {
      cmd = 'config';
      args = interaction.options.getChannel('channel') ? ['channel'] : ['channel', 'none'];
    } else if (name === 'email') {
      cmd = 'email';
      const subject = interaction.options.getString('subject');
      const body = interaction.options.getString('body');
      args = [`${subject} || ${body}`];
    }
    try {
      await handleCommand(ctx, cmd, args);
    } catch (err) {
      console.error(err);
      await interaction.editReply('Something went wrong. Please try again.');
    }
    return;
  }
});

client.on('messageCreate', async (message) => {
  if (message.author.bot) return;
  if (message.channel.id !== CHANNEL_ID) return;

  const lines = message.content.split(/\r?\n/).map((l) => l.trim()).filter(Boolean);
  if (lines.length === 0) return;

  let title = lines[0];
  let status = 'new';
  for (const [prefix, st] of Object.entries(STATUS_PREFIX)) {
    if (title.toUpperCase().startsWith(prefix)) {
      status = st;
      title = title.slice(prefix.length).trim();
      break;
    }
  }

  const entry = {
    date: new Date().toISOString().slice(0, 10),
    title,
    status,
    body: lines.slice(1).join('\n')
  };

  try {
    const entries = await getDevlog();
    if (!Array.isArray(entries)) throw new Error('devlog.json is not an array');
    const existing = entries.findIndex((e) => e.title && e.title.toLowerCase() === title.toLowerCase());
    if (existing >= 0) {
      entries[existing] = entry;
      console.log(`Updated dev log entry: ${title}`);
    } else {
      entries.unshift(entry);
      console.log(`Added dev log entry: ${title}`);
    }
    await pushDevlog(entries);
    const reply = await interaction.fetchReply();
    await reply.react('✅');
  } catch (err) {
    console.error(err);
    try {
      const reply = await interaction.fetchReply();
      await reply.react('❌');
    } catch (ignored) {
    }
  }
});

client.on('messageCreate', async (message) => {
  if (message.author.bot) return;
  if (!message.guild) return;

  await checkSpam(message);

  if (message.content.startsWith('?')) {
    const [cmd, ...args] = message.content.trim().split(/\s+/);
    const ctx = msgCtx(message, message.mentions.users.first());
    await handleCommand(ctx, cmd.slice(1), args);
    return;
  }

  const now = Date.now();
  if (now - (lastXpAt.get(message.author.id) || 0) < config.xp.cooldownMs) return;
  lastXpAt.set(message.author.id, now);

  let xpGain = config.xp.base + Math.min(config.xp.maxLengthBonus, Math.floor(message.content.length / config.xp.lengthDivisor));
  xpGain = Math.round(xpGain * xpMultiplierFor(message.member));
  const levels = loadLevels();
  const user = levels[message.author.id] || { xp: 0, level: 0, streak: 0 };
  user.xp += xpGain;
  updateStreak(user);

  const newLevel = levelFromXp(user.xp);
  if (newLevel > user.level) {
    user.level = newLevel;
    levels[message.author.id] = user;
    saveLevels(levels);
    await syncLevelRoles(message.guild, message.author.id, newLevel);
    await announceLevelup(message.channel, message.author, user, `🎖️ <@${message.author.id}> reached level **${newLevel}**!`);
    return;
  }

  levels[message.author.id] = user;
  saveLevels(levels);
});

const antiState = {
  recentJoins: new Map(),
  lastSpam: new Map(),
  lockdownUntil: new Map(),
  prevVerification: new Map()
};

async function antiRaidAlert(guild, text) {
  let channel = null;
  if (config.antiRaid.alertChannelId) {
    try {
      channel = await client.channels.fetch(String(config.antiRaid.alertChannelId));
    } catch (ignored) {
    }
  }
  if (!channel) channel = await commandsChannel();
  if (!channel) return;
  const embed = new EmbedBuilder()
    .setColor(0xff4444)
    .setTitle('🛡️ Anti-Raid')
    .setDescription(text)
    .setTimestamp();
  const ping = config.antiRaid.alertRoleId ? `<@&${config.antiRaid.alertRoleId}>` : undefined;
  await channel.send(ping ? { content: ping, embeds: [embed] } : { embeds: [embed] });
}

async function startLockdown(guild) {
  const c = config.antiRaid;
  antiState.prevVerification.set(guild.id, guild.verificationLevel);
  antiState.lockdownUntil.set(guild.id, Date.now() + c.burst.lockdownMs);
  try {
    await guild.setVerificationLevel(GuildVerificationLevel.Highest);
  } catch (ignored) {
  }
  setTimeout(() => endLockdown(guild), c.burst.lockdownMs);
}

async function endLockdown(guild) {
  if (!((antiState.lockdownUntil.get(guild.id) || 0) > Date.now())) return;
  const prev = antiState.prevVerification.get(guild.id);
  antiState.lockdownUntil.delete(guild.id);
  antiState.prevVerification.delete(guild.id);
  if (prev !== undefined) {
    try {
      await guild.setVerificationLevel(prev);
    } catch (ignored) {
    }
  }
  await antiRaidAlert(guild, '🔓 Lockdown lifted. Verification level restored.');
}

async function checkBurst(guild, member) {
  const c = config.antiRaid;
  if (!c.enabled || !c.burst.enabled) return;
  const cutoff = Date.now() - c.burst.windowMs;
  const arr = antiState.recentJoins.get(guild.id) || [];
  arr.push({ id: member.id, t: Date.now() });
  const recent = arr.filter((j) => j.t > cutoff);
  antiState.recentJoins.set(guild.id, recent);
  if (recent.length <= c.burst.maxJoins) return;
  const inLockdown = (antiState.lockdownUntil.get(guild.id) || 0) > Date.now();
  if (!inLockdown) await startLockdown(guild);
  for (const j of recent) {
    if (j.id === guild.ownerId) continue;
    try {
      await guild.members.kick(j.id, 'Raid lockdown');
    } catch (ignored) {
    }
  }
  await antiRaidAlert(guild, `🚨 **Raid detected!** ${recent.length} members joined within ${c.burst.windowMs / 1000}s. Verification raised to Highest and suspected members kicked.`);
}

async function checkNewAccount(guild, member) {
  const c = config.antiRaid;
  if (!c.enabled || !c.newAccount.enabled) return false;
  const ageDays = (Date.now() - member.user.createdAt.getTime()) / 86400000;
  if (ageDays >= c.newAccount.minAgeDays) return false;
  if (!c.newAccount.kick) {
    await antiRaidAlert(guild, `⚠️ **${member.user.username}** has a very new account (${Math.floor(ageDays)} day(s) old, limit ${c.newAccount.minAgeDays}).`);
    return false;
  }
  try {
    await guild.members.kick(member, `Account younger than ${c.newAccount.minAgeDays} days`);
    await antiRaidAlert(guild, `⚠️ Kicked **${member.user.username}** — account only ${Math.floor(ageDays)} day(s) old (limit: ${c.newAccount.minAgeDays}).`);
    return true;
  } catch (ignored) {
    return false;
  }
}

async function checkSpam(message) {
  const c = config.antiRaid;
  if (!c.enabled || !c.spam.enabled) return;
  if (message.author.bot || !message.member) return;
  const cutoff = Date.now() - c.spam.windowMs;
  const arr = (antiState.lastSpam.get(message.author.id) || []).filter((t) => t > cutoff);
  arr.push(Date.now());
  antiState.lastSpam.set(message.author.id, arr);
  if (arr.length <= c.spam.maxMessages) return;
  try {
    await message.delete();
  } catch (ignored) {
  }
  try {
    await message.member.timeout(c.spam.muteMs, 'Spam');
  } catch (ignored) {
  }
  antiState.lastSpam.delete(message.author.id);
  await antiRaidAlert(message.guild, `🗣️ **Spam detected** — timed out **${message.author.username}** for ${c.spam.muteMs / 60000} min.`);
}

client.on('guildMemberAdd', async (member) => {
  if (!SERVER_MEMBERS_INTENT) return;
  if (member.user.bot) return;
  try {
    const kicked = await checkNewAccount(member.guild, member);
    if (!kicked) await checkBurst(member.guild, member);
  } catch (err) {
    console.error(err);
  }
});

const STARBOARD_FILE = path.join(__dirname, 'starboard.json');
const EMAIL_THREADS_FILE = path.join(__dirname, 'emailThreads.json');

function loadStarboard() {
  if (!fs.existsSync(STARBOARD_FILE)) return {};
  try {
    return JSON.parse(fs.readFileSync(STARBOARD_FILE, 'utf8'));
  } catch {
    return {};
  }
}

function saveStarboard(data) {
  fs.writeFileSync(STARBOARD_FILE, JSON.stringify(data, null, 2));
}

async function starboardChannel() {
  if (config.starboard.channelId) {
    try {
      const ch = await client.channels.fetch(String(config.starboard.channelId));
      if (ch) return ch;
    } catch (ignored) {
    }
  }
  return commandsChannel();
}

async function updateStarboard(message, count, author) {
  const c = config.starboard;
  if (!c.enabled || count < c.threshold) return;
  const board = loadStarboard();
  const key = `${message.guild.id}:${message.id}`;
  const emoji = c.emoji || '⭐';
  const embed = new EmbedBuilder()
    .setColor(0xffd700)
    .setAuthor({ name: author.tag, iconURL: author.displayAvatarURL({ size: 128 }) })
    .setDescription(message.content || message.content.length ? message.content.slice(0, 1000) : '(no text content)')
    .addFields({ name: 'Source', value: `[Jump!](https://discord.com/channels/${message.guild.id}/${message.channel.id}/${message.id})` })
    .setTimestamp(message.createdAt)
    .setFooter({ text: `#${message.channel.name}` });
  if (message.attachments.size) {
    const img = message.attachments.find((a) => a.contentType && a.contentType.startsWith('image/'));
    if (img) embed.setImage(img.url);
  }
  const channel = await starboardChannel();
  if (!channel) return;

  if (board[key]) {
    try {
      const post = await channel.messages.fetch(board[key].msgId);
      await post.edit({ content: `${emoji} ${count}`, embeds: [embed] });
      board[key].count = count;
      saveStarboard(board);
    } catch (ignored) {
      delete board[key];
      saveStarboard(board);
    }
    return;
  }

  try {
    const post = await channel.send({ content: `${emoji} ${count}`, embeds: [embed] });
    board[key] = { msgId: post.id, count };
    saveStarboard(board);
  } catch (err) {
    console.error('Starboard post failed:', err.message);
  }
}

client.on('messageReactionAdd', async (reaction, user) => {
  if (user.bot) return;
  const c = config.starboard;
  if (!c.enabled) return;
  if (reaction.emoji.name !== (c.emoji || '⭐')) return;
  try {
    if (reaction.partial) await reaction.fetch();
    if (reaction.message.partial) await reaction.message.fetch();
    const message = reaction.message;
    if (!message.guild) return;
    let count = 0;
    for (const [key, r] of message.reactions.cache) {
      if (r.emoji.name === (c.emoji || '⭐')) count = r.count;
    }
    await updateStarboard(message, count, message.author);
  } catch (err) {
    console.error('Starboard reaction error:', err.message);
  }
});

client.on('messageReactionRemove', async (reaction, user) => {
  if (user.bot) return;
  const c = config.starboard;
  if (!c.enabled) return;
  if (reaction.emoji.name !== (c.emoji || '⭐')) return;
  try {
    if (reaction.partial) await reaction.fetch();
    if (reaction.message.partial) await reaction.message.fetch();
    const message = reaction.message;
    if (!message.guild) return;
    let count = 0;
    for (const [key, r] of message.reactions.cache) {
      if (r.emoji.name === (c.emoji || '⭐')) count = r.count;
    }
    if (count < c.threshold) {
      const board = loadStarboard();
      const key = `${message.guild.id}:${message.id}`;
      if (board[key]) {
        const channel = await starboardChannel();
        try {
          if (channel) await channel.messages.delete(board[key].msgId);
        } catch (ignored) {
        }
        delete board[key];
        saveStarboard(board);
      }
    } else {
      await updateStarboard(message, count, message.author);
    }
  } catch (err) {
    console.error('Starboard reaction remove error:', err.message);
  }
});

function loadEmailThreads() {
  if (!fs.existsSync(EMAIL_THREADS_FILE)) return {};
  try {
    return JSON.parse(fs.readFileSync(EMAIL_THREADS_FILE, 'utf8'));
  } catch {
    return {};
  }
}

function saveEmailThreads(data) {
  fs.writeFileSync(EMAIL_THREADS_FILE, JSON.stringify(data, null, 2));
}

// Find an existing inbox thread for a user, or create one in the email channel
async function findOrCreateInboxThread(user, threads) {
  const ch = await emailChannel();
  if (!ch) return null;
  const existing = threads[user.id];
  if (existing && existing.threadId) {
    try {
      const thread = await ch.threads.fetch(existing.threadId);
      if (thread) return thread;
    } catch (ignored) {
    }
  }
  const base = `inbox-${user.username}`.slice(0, 95);
  const thread = await ch.threads.create({
    name: base,
    autoArchiveDuration: 60,
    type: 'GUILD_PUBLIC_THREAD',
    reason: 'Hadasphere facility email inbox'
  });
  threads[user.id] = { threadId: thread.id };
  saveEmailThreads(threads);
  return thread;
}

// Look up the user an inbox thread belongs to
function ownerOfThread(threadId) {
  const threads = loadEmailThreads();
  for (const [id, rec] of Object.entries(threads)) {
    if (rec.threadId === threadId) return id;
  }
  return null;
}

// Incoming: a user DMs the bot -> post their message into their inbox thread
async function handleIncomingDm(message) {
  const threads = loadEmailThreads();
  const thread = await findOrCreateInboxThread(message.author, threads);
  if (!thread) {
    await message.reply('📧 The facility mailroom is not configured. Please ask an admin to run `?config email <#channel>`.');
    return;
  }
  const lines = message.content.split(/\r?\n/).map((l) => l.trim()).filter(Boolean);
  const subject = lines[0] || '(no subject)';
  const body = lines.slice(1).join('\n');
  const embed = emailEmbed({
    fromName: message.author.username,
    fromAddress: `${message.author.username.toLowerCase().replace(/[^a-z0-9]+/g, '.')}@external.hadasphere.facility`,
    toName: 'Facility Staff',
    subject,
    body,
    signature: 'Incoming transmission'
  });
  await thread.send({ embeds: [embed] });
  await message.reply('📧 Your email has been delivered to the facility mailroom. Replies will arrive here.');
}

client.on('messageCreate', async (message) => {
  if (message.author.bot) return;
  if (message.guild) return; // DM only

  // allow prefix commands in the bot's DM too
  if (message.content.startsWith('?')) {
    const [cmd, ...args] = message.content.trim().split(/\s+/);
    const ctx = msgCtx(message, message.mentions.users.first());
    await handleCommand(ctx, cmd.slice(1), args);
    return;
  }
  await handleIncomingDm(message);
});

// Outgoing: an admin replies inside an inbox thread -> DM the user an email
client.on('messageCreate', async (message) => {
  if (message.author.bot) return;
  if (!message.guild) return;
  if (typeof message.channel.isThread !== 'function' || !message.channel.isThread()) return;
  const threadId = message.channel.id;
  const ownerId = ownerOfThread(threadId);
  if (!ownerId) return;
  const canReply = message.member && message.member.permissions.has('ManageGuild');
  if (!canReply) return;

  const user = await client.users.fetch(ownerId).catch(() => null);
  if (!user) return;
  const embed = emailEmbed({
    fromName: 'Facility Staff',
    fromAddress: 'staff@hadasphere.facility',
    toName: user.username,
    toAddress: `${user.username.toLowerCase().replace(/[^a-z0-9]+/g, '.')}@external.hadasphere.facility`,
    subject: 'Re: your email to the facility',
    body: message.content,
    signature: message.member.displayName
  });
  try {
    const dm = await user.createDM();
    await dm.send({ embeds: [embed] });
    await message.react('📧');
  } catch (err) {
    console.error('Email reply DM failed:', err.message);
    await message.reply('⚠️ Could not deliver the reply — that user has DMs closed.');
  }
});

client.login(process.env.BOT_TOKEN);
