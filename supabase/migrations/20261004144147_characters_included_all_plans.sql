-- Character choice is included with every subscription tier.
-- This catalog metadata does not change account tiers, credits or tool entitlements.
update public.characters
set tier_required = 'basic';

update public.characters set description = case id
  when 'jj' then 'Curious, thoughtful, and always ready to chat. Included on every plan.'
  when 'phil' then 'A helpful, confident guide who makes everyday tasks easier. Included on every plan.'
  when 'chee_chai_chee' then 'A dark cyber-mystic wizard for bold ideas and thoughtful strategies. Included on every plan.'
  when 'yuna' then 'An elegant, imaginative and strategic creative companion. Included on every plan.'
  when 'ji_a' then 'A calm, thoughtful guide for clear thinking and focused assistance. Included on every plan.'
  else description
end
where id in ('jj', 'phil', 'chee_chai_chee', 'yuna', 'ji_a');
