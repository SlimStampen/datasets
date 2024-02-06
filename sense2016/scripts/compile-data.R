library(data.table)
library(purrr)
library(tidyr)
library(forcats)


# Materials ----------------------------------------------------

# Swahili vocabulary
vocab_list <- fread(file.path("sense2016", "data", "vocab_list.csv"))

# Biopsychology
biopsych_list_url <- "https://github.com/fsense/parameter-stability-paper/raw/master/materials/biopsych/biopsych_material.xlsx"
biopsych_tempfile <- tempfile()
download.file(biopsych_list_url, biopsych_tempfile)
biopsych_list <- readxl::read_excel(biopsych_tempfile)
unlink(biopsych_tempfile)
setDT(biopsych_list)
setnames(biopsych_list, old = c("WORD", "DEFINITION"), new = c("answer", "cue"))


# Flags
flags_list_url <- "https://api.github.com/repos/fsense/parameter-stability-paper/contents/materials/flags"
flags_list <- httr::GET(flags_list_url) |>
  httr::content("text") |>
  jsonlite::fromJSON() |>
  setDT()

flags_list <- flags_list[, .(cue = "", answer = stringr::str_remove(name, ".svg.png"))]

# Maps
maps_list_url <- "https://api.github.com/repos/fsense/parameter-stability-paper/contents/materials/maps"
maps_list <- httr::GET(maps_list_url) |>
  httr::content("text") |>
  jsonlite::fromJSON() |>
  setDT()

maps_list <- maps_list[, .(cue = "", answer = stringr::str_remove(name, ".png"))]

# Combine materials
materials_list <- rbindlist(list(vocab_list, biopsych_list, flags_list, maps_list), use.names = TRUE)

materials_list[, cue := tolower(cue)]
materials_list[, answer := tolower(answer)]

# Practice data -----------------------------------------------------------

d_practice_url <- "https://github.com/fsense/parameter-stability-paper/raw/master/data/MODEL_data.csv"
d_practice_raw <- fread(d_practice_url)

# Replace subject identifiers with consistently formatted IDs
d_practice_raw[, subj := as.factor(subj)]
d_subj <- d_practice_raw[, .(subj = unique(subj))]
d_subj[, subj_id := fct_anon(subj, prefix = "subj_")]
d_practice_raw[d_subj, subj := i.subj_id, on = "subj"]

# Remove duplicates
# Some participants did a block more than once.
# In those cases we'll remove all the data from these participants.
duplicates <- d_practice_raw[, .N, by = .(subj, block, rep)][N > 1]
duplicates[, unique(subj)]
d_practice <- d_practice_raw[!subj %in% duplicates[, unique(subj)]]


# Fix rows with erroneous column shift
d_practice[, RT := as.numeric(RT)] |>
  suppressWarnings()
d_practice[, duration := as.double(duration)]
d_practice_shift <- d_practice[is.na(RT)][, RT := NULL]
setnames(d_practice_shift,
         old = colnames(d_practice_shift),
         new = c(colnames(d_practice_shift)[1:5], "RT", colnames(d_practice_shift)[6:15])
)
d_practice_shift[, estRT := NA]
d_practice_shift[, duration := as.double(duration)]
d_practice[is.na(RT)] <- d_practice_shift

# Block order was randomised between participants.
d_blockorder_url <- "https://github.com/fsense/parameter-stability-paper/raw/master/data/data_for_Friederike.csv"
d_blockorder <- fread(d_blockorder_url)
d_blockorder <- d_blockorder[, .(session = session[1]), by  = .(subj, block)]
d_blockorder[, subj := as.factor(subj)]
d_blockorder[d_subj, subj := i.subj_id, on = "subj"]

practice_by_block <- d_practice[, .(answer = unique(tolower(resp[isCorrect == TRUE]))), by  = .(block, item)][materials_list, on = .(answer)]
practice_by_block <- practice_by_block[!is.na(block)] # Each block only had 25 items, so remove unused items from longer lists
setorder(practice_by_block, block, item)

d_practice_all <- d_practice[d_blockorder, on = .(subj, block)]

d_practice_clean <- practice_by_block[d_practice_all, on = .(block, item)][,
                                                                           .(subj = subj,
                                                                             session = as.factor(session),
                                                                             block = as.factor(block),
                                                                             trial = as.numeric(rep),
                                                                             time,
                                                                             item = as.factor(item),
                                                                             presentation,
                                                                             type = as.factor(type),
                                                                             cue,
                                                                             answer,
                                                                             response = resp,
                                                                             correct = isCorrect,
                                                                             rt = RT
                                                                           )
]

setorder(d_practice_clean, subj, session, block, time)
fwrite(d_practice_clean, file.path("sense2016", "data", "practice_data.csv"))




# Test data ---------------------------------------------------------------

d_test_urls <- c("https://github.com/fsense/parameter-stability-paper/raw/master/data/TEST_vocab1.csv",
                 "https://github.com/fsense/parameter-stability-paper/raw/master/data/TEST_vocab2.csv",
                 "https://github.com/fsense/parameter-stability-paper/raw/master/data/TEST_vocab.csv",
                 "https://github.com/fsense/parameter-stability-paper/raw/master/data/TEST_biopsych.csv",
                 "https://github.com/fsense/parameter-stability-paper/raw/master/data/TEST_flags.csv",
                 "https://github.com/fsense/parameter-stability-paper/raw/master/data/TEST_maps.csv")

d_test <- map_dfr(d_test_urls, function(url) {
  d <- fread(url)
  d[, Timestamp := NULL]
  pivot_longer(d,
               cols = -c(1,27),
               names_to = "answer",
               values_to = "response")
})

setDT(d_test)

# Replace subject identifiers with consistently formatted IDs
d_test[, subj := as.factor(subj)]
d_test[d_subj, subj := i.subj_id, on = "subj"]

d_test[, correct := tolower(response) == answer]
d_test_clean <- d_test[practice_by_block, on = .(block, answer)][,
                                                                 .(subj = as.factor(subj),
                                                                   block = as.factor(block),
                                                                   item = as.factor(item),
                                                                   cue,
                                                                   answer,
                                                                   response,
                                                                   correct)
]

# Remove test data from participants with duplicate practice sessions
d_test_clean <- d_test_clean[!subj %in% duplicates[, unique(subj)]]

fwrite(d_test_clean, file.path("sense2016", "data", "test_data.csv"))
