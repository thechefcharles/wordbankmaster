-- ============================================================
-- WordBank puzzle library (fresh start). Each puzzle: phrase + category +
-- subcategory + a witty one-line clue (the in-game hint).
--
-- The database was wiped to start over. To re-wipe before reseeding:
--   DELETE FROM public.daily_puzzle_schedule;
--   DELETE FROM public.arcade_runs;
--   DELETE FROM public.daily_sessions;
--   DELETE FROM public.daily_puzzles;
-- (game_results / profiles have no puzzle FK and are preserved.)
--
-- Categories (12): Movies & TV, Music, Famous People, Food & Drink,
-- Places & Travel, Sports, Phrases & Sayings, Science & Nature,
-- Books & Characters, Video Games, Brands & Logos, Tech & Internet.
-- ============================================================

ALTER TABLE public.daily_puzzles ADD COLUMN IF NOT EXISTS clue TEXT;

-- ---- Movies & TV (50) -------------------------------------------------------
INSERT INTO public.daily_puzzles (phrase, category, subcategory, clue) VALUES
('Pulp Fiction','Movies & TV 🎬','Crime','A hitman, a boxer, and a briefcase nobody should open.'),
('The Big Lebowski','Movies & TV 🎬','Cult Comedy','A stolen rug, a kidnapping mix-up, and a guy who just wants to bowl.'),
('Blade Runner','Movies & TV 🎬','Sci-Fi','Hunting rogue androids in a city that never stops raining.'),
('There Will Be Blood','Movies & TV 🎬','Drama','An oilman gets rich and loses his soul, one milkshake at a time.'),
('Jurassic Park','Movies & TV 🎬','Blockbuster','A rich guy clones dinosaurs; the dinosaurs have other plans.'),
('The Shining','Movies & TV 🎬','Horror','All work and no play makes this hotel extremely murdery.'),
('Forrest Gump','Movies & TV 🎬','Drama','Life is a box of chocolates and this guy ate the whole sampler.'),
('Fight Club','Movies & TV 🎬','Cult','The first rule is you do not talk about it. Whoops.'),
('Groundhog Day','Movies & TV 🎬','Comedy','A grumpy weatherman relives the same awful day on a loop.'),
('Mean Girls','Movies & TV 🎬','Comedy','A burn book, a new girl, and on Wednesdays we wear pink.'),
('The Matrix','Movies & TV 🎬','Sci-Fi','Red pill, blue pill, and a whole lot of dodging bullets.'),
('Home Alone','Movies & TV 🎬','Holiday','A family forgets their kid; two burglars regret everything.'),
('Mrs Doubtfire','Movies & TV 🎬','Comedy','A dad in a wig and pearls just to babysit his own kids.'),
('Kill Bill','Movies & TV 🎬','Action','A bride wakes from a coma with a very long revenge list.'),
('No Country for Old Men','Movies & TV 🎬','Thriller','A briefcase of cash and a killer with a terrible haircut.'),
('The Grand Budapest Hotel','Movies & TV 🎬','Comedy','A concierge, a stolen painting, and a lot of pink symmetry.'),
('Get Out','Movies & TV 🎬','Horror','Meeting her parents has never been this terrifying.'),
('La La Land','Movies & TV 🎬','Musical','Jazz, big dreams, and a bittersweet dance under city stars.'),
('Black Swan','Movies & TV 🎬','Drama','A ballerina slowly loses her mind chasing the perfect role.'),
('Parasite','Movies & TV 🎬','Thriller','One broke family schemes its way into a very rich basement.'),
('Toy Story','Movies & TV 🎬','Animated','What your toys actually get up to the second you leave.'),
('The Lion King','Movies & TV 🎬','Animated','A prince cub, a wise father, and one very treacherous uncle.'),
('Shrek','Movies & TV 🎬','Animated','An ogre, a chatty donkey, and a swamp that needs its privacy.'),
('Finding Nemo','Movies & TV 🎬','Animated','A nervous dad fish crosses an ocean to find his lost son.'),
('Back to the Future','Movies & TV 🎬','Sci-Fi','A DeLorean, 88 miles per hour, and an awkward run-in with mom.'),
('Top Gun','Movies & TV 🎬','Action','The need for speed, mirrored aviators, and beach volleyball.'),
('The Silence of the Lambs','Movies & TV 🎬','Thriller','A rookie agent trades clues with a cannibal to catch a killer.'),
('Goodfellas','Movies & TV 🎬','Crime','As far back as he can remember, he always wanted to be a gangster.'),
('The Departed','Movies & TV 🎬','Crime','A cop and a crook quietly swap sides inside the Boston mob.'),
('Inception','Movies & TV 🎬','Sci-Fi','A heist inside a dream, inside a dream, inside a dream.'),
('Django Unchained','Movies & TV 🎬','Western','A freed gunslinger shoots his way to rescue his wife.'),
('The Truman Show','Movies & TV 🎬','Drama','His entire life is a TV set, and he is the last to know.'),
('Donnie Darko','Movies & TV 🎬','Cult','A troubled teen, a doomsday countdown, and a very creepy rabbit.'),
('Requiem for a Dream','Movies & TV 🎬','Drama','Four big dreams spiral into one brutal, unforgettable crash.'),
('Napoleon Dynamite','Movies & TV 🎬','Comedy','Tater tots, llamas, and the best worst dance moves in Idaho.'),
('Breaking Bad','Movies & TV 🎬','Drama','A mild chemistry teacher cooks up a very illegal retirement plan.'),
('The Office','Movies & TV 🎬','Comedy','A paper company, a clueless boss, and a documentary nobody wanted.'),
('Stranger Things','Movies & TV 🎬','Sci-Fi','Small-town kids, a missing boy, and a monster from the Upside Down.'),
('Game of Thrones','Movies & TV 🎬','Fantasy','Dragons, betrayal, and a pointy chair nobody should sit in.'),
('The Sopranos','Movies & TV 🎬','Drama','A mob boss spills all his secrets to a very patient therapist.'),
('Friends','Movies & TV 🎬','Comedy','Six pals, one couch, and a coffee shop they never seem to pay for.'),
('The Wire','Movies & TV 🎬','Drama','Cops and dealers in Baltimore, told from every angle.'),
('Mad Men','Movies & TV 🎬','Drama','Cigarettes, secrets, and selling the American dream in the sixties.'),
('Better Call Saul','Movies & TV 🎬','Drama','Before he was a shady lawyer, he was just a guy named Jimmy.'),
('Curb Your Enthusiasm','Movies & TV 🎬','Comedy','One man finds a brand-new way to ruin every social situation.'),
('Twin Peaks','Movies & TV 🎬','Mystery','Who killed Laura Palmer? Also, that is some damn fine coffee.'),
('Black Mirror','Movies & TV 🎬','Sci-Fi','Technology, but make it your absolute worst nightmare.'),
('Ted Lasso','Movies & TV 🎬','Comedy','An American coaches British soccer on pure relentless optimism.'),
('Arrested Development','Movies & TV 🎬','Comedy','A wealthy family loses everything except their terrible decisions.'),
('The Mandalorian','Movies & TV 🎬','Sci-Fi','A lone bounty hunter goes soft for a very small green boss.');

-- ---- One sample per remaining category (placeholders until each is filled to ~50)
INSERT INTO public.daily_puzzles (phrase, category, subcategory, clue) VALUES
('Bohemian Rhapsody','Music 🎵','Rock','Six minutes of opera, headbanging, and is this the real life?'),
('Albert Einstein','Famous People 🌟','Science','Wild hair, wilder physics, and a tongue out for the camera.'),
('Chicken Parmesan','Food & Drink 🍔','Italian','Breaded, fried, and smothered in sauce and cheese. Comfort on a plate.'),
('The Eiffel Tower','Places & Travel ✈️','Landmarks','Parisians once hated this iron giant; now everyone proposes under it.'),
('Hail Mary','Sports 🏆','Football','A desperate last-second heave and a prayer into the end zone.'),
('Bite the Bullet','Phrases & Sayings 🗣️','Idioms','Grit your teeth and just get the painful thing over with.'),
('The Solar System','Science & Nature 🔬','Space','Eight planets, one star, and a dwarf we all still feel bad about.'),
('Sherlock Holmes','Books & Characters 📚','Mystery','A pipe, a violin, and a deduction that makes everyone feel slow.'),
('Donkey Kong','Video Games 🎮','Retro','A barrel-tossing ape, a trapped girl, and a very determined plumber.'),
('Coca Cola','Brands & Logos 🏷️','Drinks','A secret recipe, a red can, and the most famous fizz on Earth.'),
('Artificial Intelligence','Tech & Internet 💻','Tech','Machines that learn, chat, and occasionally just make things up.');
