# install packages:

library(SlimStampeRData)
library(here)
library(dplyr)
library(data.table)
library(readr)
library(tidyr)
library(ggplot2)

# define some necessary model functions:
estimate_reaction_time_from_activation <- function (activation, reading_time) {
  return((1.0 * exp(-activation) + (reading_time / 1000)) * 1000)
}

get_reading_time <- function (text) {
  word_count = length(strsplit(text, " ")[[1]])
  if (word_count > 1) {
    character_count <- nchar(text)
    return(max((-157.9 + character_count * 19.5), 300))
  }
  return(300)
}

# load csv data as df:
dat <- read_csv(here("sense2016", "data", "practice_data.csv"))

# rename variables:
dat <- dat %>% 
  dplyr::rename(
    userId = subj,
    sessionId = session,
    presentationStartTime = time,
    factText = cue,
    reactionTime = rt,
    repetition = presentation,
    lessonId = block
  ) %>%  
  drop_na(correct) 

# create a factId:
dat <- dat %>% dplyr::group_by(answer) %>%
  dplyr::mutate(factId = cur_group_id()) %>% ungroup()

# convert session time and presenation start time from s to ms:
dat$sessionTime <- dat$presentationStartTime
dat$sessionTime = dat$sessionTime * 1000
dat$presentationStartTime = dat$presentationStartTime * 1000

# calculate item repetitions:
dat <- calculate_repetition(dat)

# calculate alpha and activation:
dat <- calculate_alpha_and_activation(dat)

# calculate reading time:
dat$textText <- as.character(dat$factText)
dat$readingTime <- get_reading_time(dat$factText)

# calcualte estimated RT:
dat$estimatedLatency <- estimate_reaction_time_from_activation(dat$activation, dat$readingTime)

# plot rof for a participant to see if everything looks ok:
sum <- dat %>% filter(userId == "subj_14" & lessonId == 'vocab3') 

ggplot(sum, aes(x = as.factor(repetition), y = alpha, color = as.factor(answer), shape = correct, group = as.factor(answer))) +
  geom_point(size = 2, alpha = 0.6) +
  geom_line(linewidth = 1, alpha = 0.6) +  
  xlab('Repetition') + 
  ylab('Rate of forgetting') + 
  theme_bw() +  
  theme(axis.text.x=element_text(size=10), axis.text.y=element_text(size=10), axis.title=element_text(size=15))

# save data as csv:
write_csv(dat, here("sense2016", "data", "practice_data_alpha_act_estRT.csv"))
