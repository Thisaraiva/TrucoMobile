import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:truco_mobile/src/config/general_config.dart';
import 'package:truco_mobile/src/model/card_model.dart';
import 'package:truco_mobile/src/model/played_card_model.dart';
import 'package:truco_mobile/src/model/player_model.dart';
import 'package:truco_mobile/src/service/api_service.dart';
import 'package:truco_mobile/src/widget/custom_toast.dart';

class GameControllerProvider extends ChangeNotifier {
  List<PlayerModel> players;
  int currentRound = 0;
  bool _gameStarted = false;
  bool _newRound = false;
  CollectionReference games = FirebaseFirestore.instance.collection('games');
  ApiService apiService = ApiService(baseUrl: deckApi);
  GameControllerProvider({required this.players});

  bool get gameStarted => _gameStarted;
  set gameStarted(bool value) => _gameStarted = value;
  bool get newRound => _newRound;
  set newRound(bool value) => _newRound = value;

  Future<Object> manageGame(String roomId, bool newRound, int totalPlayers, [bool? newGame = false]) async {
    DocumentSnapshot gameSnapshot = await games.doc(roomId).get();
    
    if (gameSnapshot.exists && !newRound) {
      var gameData = gameSnapshot.data() as Map<String, dynamic>;
      var deck = gameData['deck'];
      var manilha = CardModel.fromMap(deck['manilha']);
      var cards = (deck['cards'] as List).map((item) => CardModel.fromMap(item)).toList();
      
      distributeCardsFromFirestore(cards);
      adjustCardsRankByManilha(players, manilha);
      
      notifyListeners();
      return gameData;
    }

    var deck = await apiService.createNewDeck(deckApiCards);
    var deckId = deck['deck_id'];
    var drawnCards = await apiService.drawCards(deckId, 6);
    var manilha = await apiService.drawCards(deckId, 1);
    var cardsAsList = (drawnCards['cards'] as List)
        .map((item) => CardModel.fromMap(item))
        .toList();
    distributeCards(drawnCards);
    adjustCardsRankByManilha(players, CardModel.fromMap(manilha['cards'][0]));

    var gameData = {
      'deckId': deckId,
      'manilha': CardModel.fromMap(manilha['cards'][0]),
      'cards': cardsAsList,
    };

    if (newGame != null && newGame) {
      resetPoints();
      await saveGameToFirestore(roomId, deckId, gameData, newGame, totalPlayers);
    }

    if (newGame == false && newRound) {
      return {
        'deckId': deckId,
        'manilha': CardModel.fromMap(manilha['cards'][0]),
        'cards': (drawnCards['cards'] as List)
            .map((item) => CardModel.fromMap(item))
            .toList(),
      };
    }

    notifyListeners();
    return gameData;
  }

  // void startNewRound(String roomId) async {
  //   newRound = true;

  //   var gameData = await manageGame(roomId, true);
  //   notifyListeners();
  // }

  void distributeCardsFromFirestore(List<CardModel> cards) {
    for (var i = 0; i < cards.length; i++) {
      players[i % players.length].hand.add(cards[i]);
    }
    notifyListeners();
  }

  void distributeCards(drawnCards) {
    for (var i = 0; i < drawnCards['cards'].length; i++) {
      CardModel card = CardModel.fromMap(drawnCards['cards'][i]);
      players[i % players.length].hand.add(card);
    }
    notifyListeners();
  }

  void adjustCardsRankByManilha(List<PlayerModel> players, CardModel manilha) {
    for (var player in players) {
      for (var card in player.hand) {
        if (isCardValueEqualToNextValue(manilha.rank, card.rank)) {
          card.rank = CardModel.adjustCardValue(card);
        }
      }
    }
    notifyListeners();
  }

  bool isGameFinished() {
    return players[0].score < 12 &&
        players[1].score < 12 &&
        players[0].hand.isEmpty &&
        players[1].hand.isEmpty;
  }

  bool verifyIfAnyPlayerWonTwoRounds() {
    for (var player in players) {
      if (player.hasWonTwoRounds()) {
        player.winGameAndResetRounds();
        return true;
      }
    }
    return false;
  }

  /*void distributeCards(drawnCards) {
    for (var i = 0; i < drawnCards['cards'].length; i++) {
      CardModel card = CardModel.fromMap(drawnCards['cards'][i]);
      players[i % players.length].hand.add(card);
    }
    notifyListeners();
  }*/

  void markRoundAsWon(PlayerModel winningPlayer, int roundNumber) {
    winningPlayer.winRound(roundNumber);
    currentRound = roundNumber;
    currentRound++;
  }

  void resetPoints() {
    for (var i = 0; i < players.length; i++) {
      players[i].score = 0;
    }
    notifyListeners();
  }

  void resetPlayersHand() {
    for (var i = 0; i < players.length; i++) {
      players[i].hand.clear();
    }
    notifyListeners();
  }

  bool isCardValueEqualToNextValue(int manilhaRank, nextValue) {
    return manilhaRank + 1 == nextValue;
  }

  /*void adjustCardsRankByManilha(List<PlayerModel> players, CardModel manilha) {
    players.forEach((player) {
      player.hand.forEach((card) {
        if (isCardValueEqualToNextValue(manilha.rank, card.rank)) {
          card.rank = CardModel.adjustCardValue(card);
        }
      });
    });
    notifyListeners();
  }*/

  Map<String, Object> processPlayedCards(List<PlayedCard> playedCards) {
    var cards = playedCards
        .map((playedCard) =>
            {'rank': playedCard.card.rank, 'player': playedCard.player})
        .toList();

    var card1Rank = cards[0]['rank'] as int;
    var card2Rank = cards[1]['rank'] as int;
    var rankDifference = card1Rank - card2Rank;

    if (rankDifference == 0) {
      return {
        'cards': [cards[0], cards[1]],
      };
    }

    cards.sort((a, b) => (a['rank'] as Comparable).compareTo(b['rank']));

    var highestRankCard = cards.last;
    notifyListeners();
    return highestRankCard;
  }

  void returnCardsAndShuffle(deckId) async {
    await apiService.returnCardsToDeck(deckId);
    await apiService.shuffleDeck(deckId);
    notifyListeners();
  }

  bool isHandFinished(List<PlayerModel> players, int roundNumber) {
    return roundNumber == 2;
  }

  bool checkTheRoundWinner(PlayerModel player, highestRankCard) {
    return highestRankCard['player'] == player && player.score < 12;
  }

  bool playerHasTwoRoundWins(PlayerModel player) {
    return player.roundsWinsCounter == 2;
  }

  bool isRoundTied(highestRankCard) {
    return highestRankCard['cards'].length == 2;
  }

  int checkWhoWins(highestRankCard, int roundNumber) {
    if (isHandFinished(players, roundNumber)) {
      players[0].resetRoundWins();
      players[1].resetRoundWins();
      resetPlayersHand();
    }

    if (checkTheRoundWinner(players[0], highestRankCard)) {
      showRoundWinnerToast(roundNumber, highestRankCard);
      markRoundAsWon(players[0], roundNumber);
      players[0].roundsWinsCounter++;

      if (playerHasTwoRoundWins(players[0])) {
        players[0].score += 1;
        showHandWinnerToast(roundNumber, highestRankCard);
        players[0].roundsWinsCounter = 0;
        resetPlayersHand();
      }
    } else if (checkTheRoundWinner(players[1], highestRankCard)) {
      showRoundWinnerToast(roundNumber, highestRankCard);
      markRoundAsWon(players[1], roundNumber);
      players[1].roundsWinsCounter++;
      if (playerHasTwoRoundWins(players[1])) {
        players[1].score += 1;
        showHandWinnerToast(roundNumber, highestRankCard);
        players[1].roundsWinsCounter = 0;
        resetPlayersHand();
      }
    } else if (isRoundTied(highestRankCard)) {
      showTiedRoundToast(roundNumber);
      players[0].roundsWinsCounter++;
      players[1].roundsWinsCounter++;
      markRoundAsWon(players[0], roundNumber);
      markRoundAsWon(players[1], roundNumber);

      if (players[0].roundsWinsCounter == 2 ||
          players[1].roundsWinsCounter == 2) {
        resetPlayersHand();
      }
    }
    notifyListeners();
    return players.indexOf(highestRankCard['player']);
  }

  Future<void> saveGameToFirestore(String roomId, String deckId, Map<String, dynamic> gameData, bool newGame, int totalPlayers) async {
    var manilhas = gameData['manilha'] as CardModel;
    var toMapManilha = manilhas.toMap();
    var cards = gameData['cards'] as List<CardModel>;
    var toMapCards = cards.map((card) => card.toMap()).toList();

    try {
      await games.doc(roomId).set({ 
        'deck': {
          'deckId': deckId,
          'manilha': toMapManilha,
          'cards': toMapCards,
        },
        'totalPlayers': totalPlayers,
        'newGame': newGame
      });
      notifyListeners();
    } catch (e) {
      print('Error saving game to Firestore: $e');
    }
  }
}